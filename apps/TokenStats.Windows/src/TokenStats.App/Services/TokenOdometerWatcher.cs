using TokenStats.Core;

namespace TokenStats.App.Services;

public sealed record AgentTokenSlice(string Label, TokenUsage? Usage);

/// <summary>
/// Owns the Token Odometer's event-driven transcript watch and range scans.
/// The Windows app keeps this watcher active for its process lifetime so the
/// tray summary stays current. A range change keeps the last completed rows
/// available until the new scan lands, while a generation guard prevents an
/// abandoned scan from publishing.
/// </summary>
public sealed class TokenOdometerWatcher : IAsyncDisposable
{
    private static readonly TimeSpan DebounceInterval = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan DayCheckInterval = TimeSpan.FromSeconds(30);
    private readonly object _stateGate = new();
    private readonly TranscriptTokenReader _reader;
    private readonly IReadOnlyList<(string Label, string Path)> _roots;
    private readonly Func<DateTimeOffset> _now;
    private readonly TimeZoneInfo _localTimeZone;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private readonly List<FileSystemWatcher> _watchers = [];
    private CancellationTokenSource? _scanCancellation;
    private Timer? _debounceTimer;
    private Timer? _dayTimer;
    private TokenUsage? _usage;
    private IReadOnlyList<AgentTokenSlice> _perAgent = [];
    private DateOnly? _visibleDay;
    private TokenRange _selectedRange;
    private TokenRange _displayedRange;
    private TokenRange? _pendingRange;
    private string? _lastError;
    private int _generation;
    private bool _hasLoaded;
    private bool _isScanning;
    private bool _isVisible;
    private bool _disposed;

    public TokenOdometerWatcher(
        TranscriptTokenReader reader,
        IReadOnlyList<(string Label, string Path)>? roots = null,
        Func<DateTimeOffset>? now = null,
        TimeZoneInfo? localTimeZone = null,
        TokenRange initialRange = TokenRange.Today)
    {
        if (!Enum.IsDefined(initialRange))
        {
            throw new ArgumentOutOfRangeException(
                nameof(initialRange),
                initialRange,
                "The initial Token Odometer range is not supported.");
        }

        _reader = reader;
        _roots = roots ??
            AgentRegistry.All
                .Select(definition => (
                    definition.DisplayName,
                    definition.TranscriptRoot))
                .ToArray();
        _now = now ?? (() => DateTimeOffset.Now);
        _localTimeZone = localTimeZone ?? TimeZoneInfo.Local;
        _selectedRange = initialRange;
        _displayedRange = initialRange;
    }

    public event EventHandler? Changed;

    public TokenUsage? Usage
    {
        get
        {
            lock (_stateGate)
            {
                return _usage?.Clone();
            }
        }
    }

    public IReadOnlyList<AgentTokenSlice> PerAgent
    {
        get
        {
            lock (_stateGate)
            {
                return _perAgent
                    .Select(slice => new AgentTokenSlice(
                        slice.Label,
                        slice.Usage?.Clone()))
                    .ToArray();
            }
        }
    }

    public TokenRange SelectedRange
    {
        get
        {
            lock (_stateGate)
            {
                return _selectedRange;
            }
        }
    }

    public TokenRange DisplayedRange
    {
        get
        {
            lock (_stateGate)
            {
                return _displayedRange;
            }
        }
    }

    public TokenRange? PendingRange
    {
        get
        {
            lock (_stateGate)
            {
                return _pendingRange;
            }
        }
    }

    public bool HasLoaded
    {
        get
        {
            lock (_stateGate)
            {
                return _hasLoaded;
            }
        }
    }

    public bool IsScanning
    {
        get
        {
            lock (_stateGate)
            {
                return _isScanning;
            }
        }
    }

    public string? LastError
    {
        get
        {
            lock (_stateGate)
            {
                return _lastError;
            }
        }
    }

    public Task SetVisibleAsync(bool visible)
    {
        ThrowIfDisposed();
        if (!visible)
        {
            StopWatching();
            return Task.CompletedTask;
        }

        ScanRequest request;
        lock (_stateGate)
        {
            if (_isVisible)
            {
                request = BeginScanLocked(_selectedRange);
            }
            else
            {
                _isVisible = true;
                _visibleDay = CurrentDay();

                // Arm the filesystem watchers before the seed scan so an
                // append during enumeration cannot be missed.
                CreateWatchersLocked();
                _dayTimer = new Timer(
                    _ => CheckForDayChange(),
                    null,
                    DayCheckInterval,
                    DayCheckInterval);
                // Keep the last completed rows and their displayed range while
                // the selected range is rescanned. On the first appearance,
                // HasLoaded is still false and the same path supplies the
                // initial pending/scanning state.
                request = BeginScanLocked(_selectedRange);
            }
        }

        Changed?.Invoke(this, EventArgs.Empty);
        return ScanAsync(request);
    }

    public Task SelectRangeAsync(TokenRange range)
    {
        ThrowIfDisposed();
        if (!Enum.IsDefined(range))
        {
            throw new ArgumentOutOfRangeException(nameof(range));
        }

        ScanRequest? request = null;
        lock (_stateGate)
        {
            _selectedRange = range;
            if (_isVisible)
            {
                request = BeginScanLocked(range);
            }
        }

        Changed?.Invoke(this, EventArgs.Empty);
        return request is { } value
            ? ScanAsync(value)
            : Task.CompletedTask;
    }

    public Task RefreshAsync()
    {
        ThrowIfDisposed();
        ScanRequest? request = null;
        lock (_stateGate)
        {
            if (_isVisible)
            {
                CreateWatchersLocked();
                request = BeginScanLocked(_selectedRange);
            }
        }

        if (request is null)
        {
            return Task.CompletedTask;
        }

        Changed?.Invoke(this, EventArgs.Empty);
        return ScanAsync(request.Value);
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        StopWatching();
        await _refreshGate.WaitAsync().ConfigureAwait(false);
        _refreshGate.Release();
        // A FileSystemWatcher callback already queued by Windows can still
        // observe the disposed flag. Keep the semaphore alive so that callback
        // cannot race a disposed synchronization primitive.
    }

    private ScanRequest BeginScanLocked(TokenRange range)
    {
        _generation++;
        _scanCancellation?.Cancel();
        _scanCancellation?.Dispose();
        _scanCancellation = new CancellationTokenSource();
        _pendingRange = range;
        _lastError = null;
        _isScanning = true;
        return new ScanRequest(
            _generation,
            range,
            _scanCancellation.Token);
    }

    private void StopWatching()
    {
        lock (_stateGate)
        {
            _generation++;
            _isVisible = false;
            _isScanning = false;
            _pendingRange = null;
            _lastError = null;
            _scanCancellation?.Cancel();
            _scanCancellation?.Dispose();
            _scanCancellation = null;
            _debounceTimer?.Dispose();
            _debounceTimer = null;
            _dayTimer?.Dispose();
            _dayTimer = null;
            _visibleDay = null;
            DisposeWatchersLocked();
        }
    }

    private void CreateWatchersLocked()
    {
        DisposeWatchersLocked();
        foreach (var root in _roots)
        {
            if (!Directory.Exists(root.Path))
            {
                TryCreateMissingRootWatcherLocked(root.Path);
                continue;
            }

            try
            {
                var watcher = new FileSystemWatcher(root.Path, "*.jsonl")
                {
                    IncludeSubdirectories = true,
                    NotifyFilter = NotifyFilters.FileName |
                                   NotifyFilters.DirectoryName |
                                   NotifyFilters.LastWrite |
                                   NotifyFilters.Size,
                    InternalBufferSize = 16 * 1024,
                };
                watcher.Changed += Watcher_OnChanged;
                watcher.Created += Watcher_OnChanged;
                watcher.Deleted += Watcher_OnChanged;
                watcher.Renamed += Watcher_OnRenamed;
                watcher.Error += Watcher_OnError;
                watcher.EnableRaisingEvents = true;
                _watchers.Add(watcher);
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException)
            {
                // The seed scan still works when a directory cannot be watched.
            }
        }
    }

    private void TryCreateMissingRootWatcherLocked(string missingRoot)
    {
        var target = new DirectoryInfo(Path.GetFullPath(missingRoot));
        var ancestor = target.Parent;
        while (ancestor is not null && !ancestor.Exists)
        {
            target = ancestor;
            ancestor = ancestor.Parent;
        }

        if (ancestor is null)
        {
            return;
        }

        try
        {
            var watcher = new FileSystemWatcher(ancestor.FullName, target.Name)
            {
                IncludeSubdirectories = false,
                NotifyFilter = NotifyFilters.DirectoryName,
            };
            watcher.Created += Watcher_OnMissingRootChanged;
            watcher.Renamed += Watcher_OnMissingRootRenamed;
            watcher.Error += Watcher_OnError;
            watcher.EnableRaisingEvents = true;
            _watchers.Add(watcher);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            // A manual refresh will try to establish the watch again.
        }
    }

    private void DisposeWatchersLocked()
    {
        foreach (var watcher in _watchers)
        {
            watcher.EnableRaisingEvents = false;
            watcher.Changed -= Watcher_OnChanged;
            watcher.Created -= Watcher_OnChanged;
            watcher.Created -= Watcher_OnMissingRootChanged;
            watcher.Deleted -= Watcher_OnChanged;
            watcher.Renamed -= Watcher_OnRenamed;
            watcher.Renamed -= Watcher_OnMissingRootRenamed;
            watcher.Error -= Watcher_OnError;
            watcher.Dispose();
        }

        _watchers.Clear();
    }

    private void Watcher_OnChanged(object sender, FileSystemEventArgs eventArgs) =>
        QueueRefresh(rebuildWatchers: false);

    private void Watcher_OnRenamed(object sender, RenamedEventArgs eventArgs) =>
        QueueRefresh(rebuildWatchers: false);

    private void Watcher_OnMissingRootChanged(
        object sender,
        FileSystemEventArgs eventArgs) =>
        QueueRefresh(rebuildWatchers: true);

    private void Watcher_OnMissingRootRenamed(
        object sender,
        RenamedEventArgs eventArgs) =>
        QueueRefresh(rebuildWatchers: true);

    private void Watcher_OnError(object sender, ErrorEventArgs eventArgs) =>
        QueueRefresh(rebuildWatchers: true);

    private void QueueRefresh(bool rebuildWatchers)
    {
        lock (_stateGate)
        {
            if (!_isVisible || _disposed)
            {
                return;
            }

            _debounceTimer?.Dispose();
            _debounceTimer = new Timer(
                _ =>
                {
                    ScanRequest? request = null;
                    lock (_stateGate)
                    {
                        if (!_isVisible || _disposed)
                        {
                            return;
                        }

                        if (rebuildWatchers)
                        {
                            CreateWatchersLocked();
                        }

                        request = BeginScanLocked(_selectedRange);
                    }

                    Changed?.Invoke(this, EventArgs.Empty);
                    _ = ScanAsync(request.Value);
                },
                null,
                DebounceInterval,
                Timeout.InfiniteTimeSpan);
        }
    }

    private void CheckForDayChange()
    {
        ScanRequest? request = null;
        lock (_stateGate)
        {
            if (!_isVisible ||
                _disposed ||
                _visibleDay == CurrentDay())
            {
                return;
            }

            _visibleDay = CurrentDay();
            request = BeginScanLocked(_selectedRange);
        }

        Changed?.Invoke(this, EventArgs.Empty);
        _ = ScanAsync(request.Value);
    }

    private DateOnly CurrentDay() =>
        DateOnly.FromDateTime(
            TimeZoneInfo.ConvertTime(_now(), _localTimeZone).DateTime);

    private async Task ScanAsync(ScanRequest request)
    {
        try
        {
            await _refreshGate
                .WaitAsync(request.CancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        try
        {
            var slices = new List<AgentTokenSlice>(_roots.Count);
            var scanTime = _now();
            foreach (var root in _roots)
            {
                request.CancellationToken.ThrowIfCancellationRequested();
                var usage = await _reader
                    .RangeUsageAsync(
                        root.Path,
                        request.Range,
                        scanTime,
                        request.CancellationToken)
                    .ConfigureAwait(false);
                slices.Add(new AgentTokenSlice(root.Label, usage));
            }

            var combined = new TokenUsage();
            foreach (var slice in slices)
            {
                if (slice.Usage is { } usage)
                {
                    combined.Add(usage);
                }
            }

            lock (_stateGate)
            {
                if (!_isVisible ||
                    request.Generation != _generation ||
                    request.Range != _selectedRange)
                {
                    return;
                }

                _perAgent = slices;
                _usage = combined.ResponseCount > 0 ? combined : null;
                _displayedRange = request.Range;
                _pendingRange = null;
                _lastError = null;
                _hasLoaded = true;
                _isScanning = false;
            }

            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            var publish = false;
            lock (_stateGate)
            {
                if (_isVisible &&
                    request.Generation == _generation &&
                    request.Range == _selectedRange)
                {
                    _pendingRange = null;
                    _lastError = string.IsNullOrWhiteSpace(exception.Message)
                        ? exception.GetType().Name
                        : exception.Message;
                    _isScanning = false;
                    publish = true;
                }
            }

            if (publish)
            {
                Changed?.Invoke(this, EventArgs.Empty);
            }
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private readonly record struct ScanRequest(
        int Generation,
        TokenRange Range,
        CancellationToken CancellationToken);
}
