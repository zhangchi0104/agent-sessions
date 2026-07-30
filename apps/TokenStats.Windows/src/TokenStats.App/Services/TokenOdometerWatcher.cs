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
    private static readonly TimeSpan WatcherRetryInterval =
        TimeSpan.FromSeconds(30);
    private static readonly TimeSpan MaximumScanRetryInterval =
        TimeSpan.FromSeconds(30);
    private readonly object _stateGate = new();
    private readonly TranscriptTokenReader _reader;
    private readonly IReadOnlyList<(string Label, string Path)> _roots;
    private readonly Func<DateTimeOffset> _now;
    private readonly TimeZoneInfo _localTimeZone;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private readonly List<FileSystemWatcher> _watchers = [];
    private readonly HashSet<string> _changedTranscriptPaths =
        new(StringComparer.OrdinalIgnoreCase);
    private CancellationTokenSource? _scanCancellation;
    private Timer? _debounceTimer;
    private Timer? _dayTimer;
    private Timer? _scanRetryTimer;
    private Timer? _watcherRetryTimer;
    private TokenUsage? _usage;
    private IReadOnlyList<AgentTokenSlice> _perAgent = [];
    private DateOnly? _visibleDay;
    private TokenRange _selectedRange;
    private TokenRange _displayedRange;
    private TokenRange? _pendingRange;
    private string? _lastError;
    private long _changedPathsVersion;
    private long _fullReconciliationVersion;
    private int _generation;
    private int _consecutiveScanFailures;
    private bool _hasLoaded;
    private bool _isScanning;
    private bool _isVisible;
    private bool _drainPending;
    private bool _rebuildWatchersPending;
    private bool _watcherCoverageIncomplete;
    private bool _requiresFullReconciliation = true;
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

    private ScanRequest BeginScanLocked(
        TokenRange range,
        IReadOnlyList<string>? changedPaths = null)
    {
        if (changedPaths is null)
        {
            RequireFullReconciliationLocked();
        }

        if (_requiresFullReconciliation)
        {
            changedPaths = null;
        }

        _debounceTimer?.Dispose();
        _debounceTimer = null;
        _drainPending = false;
        return StartScanLocked(range, changedPaths, supersede: true);
    }

    private ScanRequest? BeginPendingScanLocked()
    {
        _drainPending = false;
        if (_isScanning)
        {
            _drainPending = true;
            return null;
        }

        if (!_requiresFullReconciliation &&
            _changedTranscriptPaths.Count == 0)
        {
            return null;
        }

        var changedPaths = _requiresFullReconciliation
            ? null
            : _changedTranscriptPaths.ToArray();
        return StartScanLocked(
            _selectedRange,
            changedPaths,
            supersede: false);
    }

    private ScanRequest StartScanLocked(
        TokenRange range,
        IReadOnlyList<string>? changedPaths,
        bool supersede)
    {
        if (_isScanning && !supersede)
        {
            throw new InvalidOperationException(
                "A queued Token Odometer scan cannot supersede an active scan.");
        }

        _generation++;
        if (_isScanning)
        {
            _scanCancellation?.Cancel();
        }
        _scanCancellation?.Dispose();
        _scanCancellation = new CancellationTokenSource();
        _scanRetryTimer?.Dispose();
        _scanRetryTimer = null;
        _pendingRange = range;
        _lastError = null;
        _isScanning = true;
        return new ScanRequest(
            _generation,
            range,
            changedPaths,
            _changedPathsVersion,
            _fullReconciliationVersion,
            _scanCancellation.Token);
    }

    private void RequireFullReconciliationLocked()
    {
        _requiresFullReconciliation = true;
        _fullReconciliationVersion++;
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
            _scanRetryTimer?.Dispose();
            _scanRetryTimer = null;
            _watcherRetryTimer?.Dispose();
            _watcherRetryTimer = null;
            _visibleDay = null;
            _changedTranscriptPaths.Clear();
            _drainPending = false;
            _rebuildWatchersPending = false;
            _watcherCoverageIncomplete = false;
            _requiresFullReconciliation = true;
            _consecutiveScanFailures = 0;
            DisposeWatchersLocked();
        }
    }

    private bool CreateWatchersLocked()
    {
        _watcherRetryTimer?.Dispose();
        _watcherRetryTimer = null;
        DisposeWatchersLocked();
        var registrationFailed = false;
        foreach (var root in _roots)
        {
            if (!Directory.Exists(root.Path))
            {
                registrationFailed |=
                    !TryCreateMissingRootWatcherLocked(root.Path);
                continue;
            }

            registrationFailed |=
                !TryCreateTranscriptWatcherLocked(root.Path);
            registrationFailed |=
                !TryCreateDirectoryWatcherLocked(root.Path);
        }

        if (registrationFailed && _isVisible && !_disposed)
        {
            _watcherRetryTimer = new Timer(
                _ => RetryWatcherRegistration(),
                null,
                WatcherRetryInterval,
                Timeout.InfiniteTimeSpan);
        }

        _watcherCoverageIncomplete = registrationFailed;
        return !registrationFailed;
    }

    private bool TryCreateTranscriptWatcherLocked(string root)
    {
        FileSystemWatcher? watcher = null;
        try
        {
            watcher = new FileSystemWatcher(root, "*.jsonl")
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.FileName |
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
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            watcher?.Dispose();
            // The seed scan still works while watcher registration retries.
            return false;
        }
    }

    private bool TryCreateDirectoryWatcherLocked(string root)
    {
        FileSystemWatcher? watcher = null;
        try
        {
            watcher = new FileSystemWatcher(root, "*")
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.DirectoryName,
                InternalBufferSize = 16 * 1024,
            };
            watcher.Created += Watcher_OnDirectoryChanged;
            watcher.Deleted += Watcher_OnDirectoryChanged;
            watcher.Renamed += Watcher_OnDirectoryRenamed;
            watcher.Error += Watcher_OnError;
            watcher.EnableRaisingEvents = true;
            _watchers.Add(watcher);
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            watcher?.Dispose();
            // File events remain covered while directory watching retries.
            return false;
        }
    }

    private bool TryCreateMissingRootWatcherLocked(string missingRoot)
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
            return false;
        }

        FileSystemWatcher? watcher = null;
        try
        {
            watcher = new FileSystemWatcher(ancestor.FullName, target.Name)
            {
                IncludeSubdirectories = false,
                NotifyFilter = NotifyFilters.DirectoryName,
            };
            watcher.Created += Watcher_OnMissingRootChanged;
            watcher.Renamed += Watcher_OnMissingRootRenamed;
            watcher.Error += Watcher_OnError;
            watcher.EnableRaisingEvents = true;
            _watchers.Add(watcher);
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            watcher?.Dispose();
            return false;
        }
    }

    private void RetryWatcherRegistration()
    {
        var recovered = false;
        lock (_stateGate)
        {
            if (!_isVisible ||
                _disposed ||
                !_watcherCoverageIncomplete)
            {
                return;
            }

            // Failed retries only restore/re-arm watcher coverage; they never
            // poll transcripts. A successful recovery is reconciled below.
            recovered = CreateWatchersLocked();
        }

        if (recovered)
        {
            // Reconcile once after coverage returns so filesystem changes made
            // while registration was unavailable cannot remain invisible.
            QueueRefresh(
                rebuildWatchers: false,
                requireFullReconciliation: true);
        }
    }

    private void DisposeWatchersLocked()
    {
        foreach (var watcher in _watchers)
        {
            watcher.EnableRaisingEvents = false;
            watcher.Changed -= Watcher_OnChanged;
            watcher.Created -= Watcher_OnChanged;
            watcher.Created -= Watcher_OnDirectoryChanged;
            watcher.Created -= Watcher_OnMissingRootChanged;
            watcher.Deleted -= Watcher_OnChanged;
            watcher.Deleted -= Watcher_OnDirectoryChanged;
            watcher.Renamed -= Watcher_OnRenamed;
            watcher.Renamed -= Watcher_OnDirectoryRenamed;
            watcher.Renamed -= Watcher_OnMissingRootRenamed;
            watcher.Error -= Watcher_OnError;
            watcher.Dispose();
        }

        _watchers.Clear();
    }

    private void Watcher_OnChanged(object sender, FileSystemEventArgs eventArgs) =>
        QueueRefresh(
            rebuildWatchers: false,
            requireFullReconciliation: false,
            eventArgs.FullPath);

    private void Watcher_OnRenamed(object sender, RenamedEventArgs eventArgs) =>
        QueueRefresh(
            rebuildWatchers: false,
            requireFullReconciliation: false,
            eventArgs.OldFullPath,
            eventArgs.FullPath);

    private void Watcher_OnDirectoryChanged(
        object sender,
        FileSystemEventArgs eventArgs) =>
        QueueRefresh(
            rebuildWatchers: false,
            requireFullReconciliation: true);

    private void Watcher_OnDirectoryRenamed(
        object sender,
        RenamedEventArgs eventArgs) =>
        QueueRefresh(
            rebuildWatchers: false,
            requireFullReconciliation: true);

    private void Watcher_OnMissingRootChanged(
        object sender,
        FileSystemEventArgs eventArgs) =>
        QueueRefresh(
            rebuildWatchers: true,
            requireFullReconciliation: true);

    private void Watcher_OnMissingRootRenamed(
        object sender,
        RenamedEventArgs eventArgs) =>
        QueueRefresh(
            rebuildWatchers: true,
            requireFullReconciliation: true);

    private void Watcher_OnError(object sender, ErrorEventArgs eventArgs) =>
        QueueRefresh(
            rebuildWatchers: true,
            requireFullReconciliation: true);

    private void QueueRefresh(
        bool rebuildWatchers,
        bool requireFullReconciliation,
        params string[] changedPaths)
    {
        lock (_stateGate)
        {
            if (!_isVisible || _disposed)
            {
                return;
            }

            var sawChangedPath = false;
            foreach (var path in changedPaths)
            {
                if (!string.IsNullOrWhiteSpace(path))
                {
                    _changedTranscriptPaths.Add(path);
                    sawChangedPath = true;
                }
            }
            if (sawChangedPath)
            {
                _changedPathsVersion++;
            }

            _rebuildWatchersPending |= rebuildWatchers;
            if (requireFullReconciliation)
            {
                RequireFullReconciliationLocked();
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

                        if (_rebuildWatchersPending)
                        {
                            CreateWatchersLocked();
                            _rebuildWatchersPending = false;
                        }

                        if (_isScanning)
                        {
                            _drainPending = true;
                            return;
                        }

                        request = BeginPendingScanLocked();
                    }

                    if (request is { } value)
                    {
                        Changed?.Invoke(this, EventArgs.Empty);
                        _ = ScanAsync(value);
                    }
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
            ScanRequest? followUp = null;
            var slices = new List<AgentTokenSlice>(_roots.Count);
            var scanTime = _now();
            foreach (var root in _roots)
            {
                request.CancellationToken.ThrowIfCancellationRequested();
                var usage = request.ChangedPaths is null
                    ? await _reader
                        .RangeUsageAsync(
                            root.Path,
                            request.Range,
                            scanTime,
                            request.CancellationToken)
                        .ConfigureAwait(false)
                    : await _reader
                        .RefreshRangeAsync(
                            root.Path,
                            request.Range,
                            request.ChangedPaths,
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
                if (request.ChangedPaths is null &&
                    request.FullReconciliationVersion ==
                        _fullReconciliationVersion)
                {
                    _requiresFullReconciliation = false;
                }

                if (request.ChangedPathsVersion ==
                    _changedPathsVersion)
                {
                    _changedTranscriptPaths.Clear();
                }

                _consecutiveScanFailures = 0;
                _scanRetryTimer?.Dispose();
                _scanRetryTimer = null;
                if (_drainPending)
                {
                    followUp = BeginPendingScanLocked();
                }
            }

            Changed?.Invoke(this, EventArgs.Empty);
            if (followUp is { } value)
            {
                _ = ScanAsync(value);
            }
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
                    RequireFullReconciliationLocked();
                    _consecutiveScanFailures = Math.Min(
                        _consecutiveScanFailures + 1,
                        6);
                    ScheduleScanRetryLocked();
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

    private void ScheduleScanRetryLocked()
    {
        _scanRetryTimer?.Dispose();
        var exponent = Math.Min(
            Math.Max(_consecutiveScanFailures - 1, 0),
            5);
        var delaySeconds = Math.Min(
            Math.Pow(2, exponent),
            MaximumScanRetryInterval.TotalSeconds);
        _scanRetryTimer = new Timer(
            _ => RetryFailedScan(),
            null,
            TimeSpan.FromSeconds(delaySeconds),
            Timeout.InfiniteTimeSpan);
    }

    private void RetryFailedScan()
    {
        ScanRequest? request;
        lock (_stateGate)
        {
            _scanRetryTimer?.Dispose();
            _scanRetryTimer = null;
            if (!_isVisible || _disposed)
            {
                return;
            }

            if (_isScanning)
            {
                _drainPending = true;
                return;
            }

            request = BeginPendingScanLocked();
        }

        if (request is { } value)
        {
            Changed?.Invoke(this, EventArgs.Empty);
            _ = ScanAsync(value);
        }
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private readonly record struct ScanRequest(
        int Generation,
        TokenRange Range,
        IReadOnlyList<string>? ChangedPaths,
        long ChangedPathsVersion,
        long FullReconciliationVersion,
        CancellationToken CancellationToken);
}
