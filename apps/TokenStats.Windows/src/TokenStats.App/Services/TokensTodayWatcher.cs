using TokenStats.Core;

namespace TokenStats.App.Services;

public sealed record AgentTokenSlice(string Label, TokenUsage Usage);

/// <summary>
/// Seeds Tokens Today when the flyout opens, then watches native Windows
/// transcript roots only for as long as the flyout remains visible.
/// </summary>
public sealed class TokensTodayWatcher : IAsyncDisposable
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
    private CancellationTokenSource? _visibleCancellation;
    private Timer? _debounceTimer;
    private Timer? _dayTimer;
    private TokenUsage? _usage;
    private IReadOnlyList<AgentTokenSlice> _perAgent = [];
    private DateOnly? _visibleDay;
    private int _generation;
    private bool _disposed;

    public TokensTodayWatcher(
        TranscriptTokenReader reader,
        IReadOnlyList<(string Label, string Path)>? roots = null,
        Func<DateTimeOffset>? now = null,
        TimeZoneInfo? localTimeZone = null)
    {
        _reader = reader;
        _roots = roots ??
            AgentRegistry.All
                .Select(definition => (definition.DisplayName, definition.TranscriptRoot))
                .ToArray();
        _now = now ?? (() => DateTimeOffset.Now);
        _localTimeZone = localTimeZone ?? TimeZoneInfo.Local;
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
                    .Select(slice => new AgentTokenSlice(slice.Label, slice.Usage.Clone()))
                    .ToArray();
            }
        }
    }

    public async Task SetVisibleAsync(bool visible)
    {
        ThrowIfDisposed();
        if (!visible)
        {
            StopWatching();
            return;
        }

        int generation;
        CancellationToken token;
        var clearedForNewDay = false;
        lock (_stateGate)
        {
            if (_visibleCancellation is null)
            {
                _generation++;
                _visibleCancellation = new CancellationTokenSource();
                _visibleDay = CurrentDay();
                ClearUsageLocked();
                clearedForNewDay = true;
                CreateWatchersLocked();
                _dayTimer = new Timer(
                    _ => CheckForDayChange(),
                    null,
                    DayCheckInterval,
                    DayCheckInterval);
            }
            else if (_visibleDay != CurrentDay())
            {
                RotateDayLocked();
                clearedForNewDay = true;
            }

            generation = _generation;
            token = _visibleCancellation.Token;
        }

        if (clearedForNewDay)
        {
            Changed?.Invoke(this, EventArgs.Empty);
        }

        await RefreshAsync(generation, token).ConfigureAwait(false);
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
        // observe cancellation after this point. Keeping this one semaphore
        // alive avoids racing that callback against Dispose.
    }

    private void StopWatching()
    {
        lock (_stateGate)
        {
            _generation++;
            _visibleCancellation?.Cancel();
            _visibleCancellation?.Dispose();
            _visibleCancellation = null;
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

    private void DisposeWatchersLocked()
    {
        foreach (var watcher in _watchers)
        {
            watcher.EnableRaisingEvents = false;
            watcher.Changed -= Watcher_OnChanged;
            watcher.Created -= Watcher_OnChanged;
            watcher.Deleted -= Watcher_OnChanged;
            watcher.Renamed -= Watcher_OnRenamed;
            watcher.Error -= Watcher_OnError;
            watcher.Dispose();
        }

        _watchers.Clear();
    }

    private void Watcher_OnChanged(object sender, FileSystemEventArgs eventArgs) =>
        QueueRefresh(rebuildWatchers: false);

    private void Watcher_OnRenamed(object sender, RenamedEventArgs eventArgs) =>
        QueueRefresh(rebuildWatchers: false);

    private void Watcher_OnError(object sender, ErrorEventArgs eventArgs) =>
        QueueRefresh(rebuildWatchers: true);

    private void QueueRefresh(bool rebuildWatchers)
    {
        lock (_stateGate)
        {
            if (_visibleCancellation is null || _disposed)
            {
                return;
            }

            var generation = _generation;
            var token = _visibleCancellation.Token;
            _debounceTimer?.Dispose();
            _debounceTimer = new Timer(
                _ =>
                {
                    if (rebuildWatchers)
                    {
                        lock (_stateGate)
                        {
                            if (generation == _generation &&
                                _visibleCancellation is not null)
                            {
                                CreateWatchersLocked();
                            }
                        }
                    }

                    _ = RefreshAsync(generation, token);
                },
                null,
                DebounceInterval,
                Timeout.InfiniteTimeSpan);
        }
    }

    private void CheckForDayChange()
    {
        int generation;
        CancellationToken token;
        lock (_stateGate)
        {
            if (_visibleCancellation is null ||
                _disposed ||
                _visibleDay == CurrentDay())
            {
                return;
            }

            RotateDayLocked();
            generation = _generation;
            token = _visibleCancellation.Token;
        }

        Changed?.Invoke(this, EventArgs.Empty);
        _ = RefreshAsync(generation, token);
    }

    private void RotateDayLocked()
    {
        _generation++;
        _visibleCancellation?.Cancel();
        _visibleCancellation?.Dispose();
        _visibleCancellation = new CancellationTokenSource();
        _visibleDay = CurrentDay();
        ClearUsageLocked();
    }

    private void ClearUsageLocked()
    {
        _usage = null;
        _perAgent = [];
    }

    private DateOnly CurrentDay() =>
        DateOnly.FromDateTime(
            TimeZoneInfo.ConvertTime(_now(), _localTimeZone).DateTime);

    private async Task RefreshAsync(
        int generation,
        CancellationToken cancellationToken)
    {
        try
        {
            await _refreshGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        try
        {
            var slices = new List<AgentTokenSlice>();
            var scanTime = _now();
            foreach (var root in _roots)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var usage = await _reader
                    .TodayUsageAsync(
                        root.Path,
                        scanTime,
                        cancellationToken)
                    .ConfigureAwait(false);
                if (usage is not null)
                {
                    slices.Add(new AgentTokenSlice(root.Label, usage));
                }
            }

            var combined = new TokenUsage();
            foreach (var slice in slices)
            {
                combined.Add(slice.Usage);
            }

            lock (_stateGate)
            {
                if (generation != _generation || _visibleCancellation is null)
                {
                    return;
                }

                _perAgent = slices;
                _usage = combined.ResponseCount > 0 ? combined : null;
            }

            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (OperationCanceledException)
        {
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
}
