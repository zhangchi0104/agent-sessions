using TokenStats.Core;

namespace TokenStats.App.Services;

public sealed record AgentPresentation(
    AgentDefinition Definition,
    AgentState State,
    bool IsRefreshing,
    string? Diagnostics,
    string? LoginError,
    bool AwaitingCode,
    bool IsSigningIn);

/// <summary>
/// Coordinates the pure state/retry rules with each agent's auth, network, and
/// persistence shells. Every agent owns independent refresh and failure state.
/// </summary>
public sealed class UsageCoordinator : IAsyncDisposable
{
    private static readonly TimeSpan SignInRestartDelay = TimeSpan.FromSeconds(2);
    private readonly object _stateGate = new();
    private readonly AppSettingsStore _settings;
    private readonly IReadOnlyDictionary<AgentId, IAgentAuthSession> _auth;
    private readonly IReadOnlyDictionary<AgentId, IUsageProvider> _providers;
    private readonly Dictionary<AgentId, AgentState> _states = [];
    private readonly Dictionary<AgentId, bool> _refreshing = [];
    private readonly Dictionary<AgentId, string?> _diagnostics = [];
    private readonly Dictionary<AgentId, string?> _loginErrors = [];
    private readonly HashSet<AgentId> _awaitingCode = [];
    private readonly HashSet<AgentId> _signingIn = [];
    private readonly HashSet<AgentId> _beginningSignIn = [];
    private readonly HashSet<AgentId> _completingSignIn = [];
    private readonly Dictionary<AgentId, DateTimeOffset> _signInStartedAt = [];
    private readonly Dictionary<AgentId, DateTimeOffset?> _lastFetch = [];
    private readonly Dictionary<AgentId, int> _failures = [];
    private readonly Dictionary<AgentId, long> _sessionGenerations = [];
    private readonly Dictionary<AgentId, SemaphoreSlim> _refreshGates = [];
    private readonly Dictionary<AgentId, CancellationTokenSource> _timers = [];
    private readonly CancellationTokenSource _lifetime = new();
    private bool _started;
    private bool _disposed;

    public UsageCoordinator(
        AppSettingsStore settings,
        IReadOnlyDictionary<AgentId, IAgentAuthSession> auth,
        IReadOnlyDictionary<AgentId, IUsageProvider> providers)
    {
        _settings = settings;
        _auth = auth;
        _providers = providers;

        foreach (var definition in AgentRegistry.All)
        {
            var id = definition.Id;
            if (!auth.ContainsKey(id) || !providers.ContainsKey(id))
            {
                throw new ArgumentException($"Missing auth or usage provider for {id}.");
            }

            _states[id] = AgentState.SignedOut;
            _refreshing[id] = false;
            _failures[id] = 0;
            _sessionGenerations[id] = 0;
            _refreshGates[id] = new SemaphoreSlim(1, 1);
        }

        _settings.Changed += Settings_OnChanged;
    }

    public event EventHandler? Changed;

    public AppearancePreferences Appearance => _settings.Appearance;

    public IReadOnlyList<AgentPresentation> Agents
    {
        get
        {
            lock (_stateGate)
            {
                return _settings.Appearance.DisplayOrder()
                    .Select(CreatePresentationLocked)
                    .ToArray();
            }
        }
    }

    public string TraySummary
    {
        get
        {
            lock (_stateGate)
            {
                return UsageFormatting.TraySummary(
                    _settings.Appearance.DisplayOrder().Select(
                        id => (AgentRegistry.Get(id), _states[id])));
            }
        }
    }

    public int ConnectedCount
    {
        get
        {
            lock (_stateGate)
            {
                return _states.Values.Count(
                    state => state.Kind != AgentStateKind.SignedOut);
            }
        }
    }

    public AgentPresentation GetAgent(AgentId id)
    {
        lock (_stateGate)
        {
            return CreatePresentationLocked(id);
        }
    }

    public async Task StartAsync()
    {
        ThrowIfDisposed();
        lock (_stateGate)
        {
            if (_started)
            {
                return;
            }

            _started = true;
            foreach (var definition in AgentRegistry.All)
            {
                var id = definition.Id;
                if (_settings.LoadLastSnapshot(id) is { } cached)
                {
                    var restored = AgentStateReducer.Reduce(
                        _states[id],
                        new AgentEvent(AgentEventKind.FetchSucceeded, cached));
                    _states[id] = AgentStateReducer.Reduce(
                        restored,
                        new AgentEvent(AgentEventKind.FetchFailed));
                }

                if (!_auth[id].IsSignedIn)
                {
                    _states[id] = AgentState.SignedOut;
                }
            }
        }

        RaiseChanged();
        await RefreshAllAsync(RefreshTrigger.Timer, _lifetime.Token)
            .ConfigureAwait(false);
    }

    public Task RefreshAllAsync(
        RefreshTrigger trigger = RefreshTrigger.Manual,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        return Task.WhenAll(
            AgentRegistry.All.Select(
                definition => RefreshAsync(
                    definition.Id,
                    trigger,
                    cancellationToken)));
    }

    public async Task RefreshAsync(
        AgentId id,
        RefreshTrigger trigger,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        var gate = _refreshGates[id];
        if (!await gate.WaitAsync(0, cancellationToken).ConfigureAwait(false))
        {
            return;
        }

        try
        {
            DateTimeOffset? lastFetch;
            int failures;
            long sessionGeneration;
            lock (_stateGate)
            {
                lastFetch = _lastFetch.GetValueOrDefault(id);
                failures = _failures.GetValueOrDefault(id);
                sessionGeneration = _sessionGenerations[id];
            }

            var decision = RefreshPolicy.Decide(
                trigger,
                lastFetch,
                DateTimeOffset.Now,
                failures);
            if (!decision.ShouldFetch)
            {
                ScheduleTimer(id, decision.NextInterval);
                return;
            }

            if (!_auth[id].IsSignedIn)
            {
                lock (_stateGate)
                {
                    _states[id] = AgentState.SignedOut;
                }

                RaiseChanged();
                ScheduleTimer(id, decision.NextInterval);
                return;
            }

            lock (_stateGate)
            {
                _states[id] = AgentStateReducer.Reduce(
                    _states[id],
                    new AgentEvent(AgentEventKind.LoadingStarted));
                _refreshing[id] = true;
            }

            RaiseChanged();
            try
            {
                using var linked = CancellationTokenSource.CreateLinkedTokenSource(
                    cancellationToken,
                    _lifetime.Token);
                var windows = await _providers[id]
                    .FetchUsageAsync(linked.Token)
                    .ConfigureAwait(false);
                if (!_auth[id].IsSignedIn)
                {
                    ScheduleTimer(id, RefreshPolicy.BaseInterval);
                    return;
                }

                var now = DateTimeOffset.Now;
                var snapshot = new UsageSnapshot(windows, now);
                var sessionChanged = false;
                lock (_stateGate)
                {
                    if (_sessionGenerations[id] != sessionGeneration)
                    {
                        sessionChanged = true;
                    }
                    else
                    {
                        // Commit cached data and presentation state under the
                        // same lock used by SignOut, so sign-out always wins.
                        _settings.SaveLastSnapshot(id, snapshot);
                        _lastFetch[id] = now;
                        _failures[id] = 0;
                        _diagnostics[id] = null;
                        _states[id] = AgentStateReducer.Reduce(
                            _states[id],
                            new AgentEvent(AgentEventKind.FetchSucceeded, snapshot));
                    }
                }

                if (sessionChanged)
                {
                    ScheduleTimer(id, RefreshPolicy.BaseInterval);
                    return;
                }
            }
            catch (OperationCanceledException) when (
                cancellationToken.IsCancellationRequested ||
                _lifetime.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                if (!_auth[id].IsSignedIn)
                {
                    ScheduleTimer(id, RefreshPolicy.BaseInterval);
                    return;
                }

                lock (_stateGate)
                {
                    if (_sessionGenerations[id] == sessionGeneration)
                    {
                        _failures[id] = _failures.GetValueOrDefault(id) + 1;
                        _diagnostics[id] = FriendlyError(exception);
                        _states[id] = AgentStateReducer.Reduce(
                            _states[id],
                            new AgentEvent(AgentEventKind.FetchFailed));
                    }
                }
            }
            finally
            {
                lock (_stateGate)
                {
                    _refreshing[id] = false;
                }

                RaiseChanged();
            }

            int currentFailures;
            DateTimeOffset? currentLastFetch;
            lock (_stateGate)
            {
                currentFailures = _failures.GetValueOrDefault(id);
                currentLastFetch = _lastFetch.GetValueOrDefault(id);
            }

            ScheduleTimer(
                id,
                RefreshPolicy.Decide(
                    RefreshTrigger.Timer,
                    currentLastFetch,
                    DateTimeOffset.Now,
                    currentFailures).NextInterval);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task BeginSignInAsync(
        AgentId id,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        var definition = AgentRegistry.Get(id);
        var canBegin = false;
        lock (_stateGate)
        {
            var now = DateTimeOffset.Now;
            var restartTooSoon =
                definition.SignInStyle == SignInStyle.PasteCode &&
                _signingIn.Contains(id) &&
                _signInStartedAt.TryGetValue(id, out var startedAt) &&
                now - startedAt < SignInRestartDelay;
            if (_beginningSignIn.Contains(id) ||
                _completingSignIn.Contains(id) ||
                (definition.SignInStyle == SignInStyle.SelfCompleting &&
                 _signingIn.Contains(id)) ||
                restartTooSoon)
            {
                _loginErrors[id] =
                    "A sign-in is already in progress for this subscription.";
            }
            else
            {
                canBegin = true;
                _beginningSignIn.Add(id);
                _signingIn.Add(id);
                _signInStartedAt[id] = now;
                _loginErrors[id] = null;
                if (definition.SignInStyle == SignInStyle.PasteCode)
                {
                    _awaitingCode.Add(id);
                }
            }
        }

        RaiseChanged();
        if (!canBegin)
        {
            return;
        }

        try
        {
            await _auth[id].BeginSignInAsync(cancellationToken).ConfigureAwait(false);
            lock (_stateGate)
            {
                _beginningSignIn.Remove(id);
                _loginErrors[id] = null;
                if (definition.SignInStyle == SignInStyle.SelfCompleting)
                {
                    _signingIn.Remove(id);
                    _signInStartedAt.Remove(id);
                    _awaitingCode.Remove(id);
                }
            }

            RaiseChanged();
            if (definition.SignInStyle == SignInStyle.SelfCompleting)
            {
                await RefreshAsync(id, RefreshTrigger.Manual, cancellationToken)
                    .ConfigureAwait(false);
            }
        }
        catch (Exception exception)
        {
            lock (_stateGate)
            {
                _beginningSignIn.Remove(id);
                _signingIn.Remove(id);
                _signInStartedAt.Remove(id);
                _awaitingCode.Remove(id);
                _loginErrors[id] = $"Sign-in failed: {FriendlyError(exception)}";
            }

            RaiseChanged();
        }
    }

    public async Task CompleteSignInAsync(
        AgentId id,
        string pastedCode,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        var canComplete = false;
        lock (_stateGate)
        {
            if (!_signingIn.Contains(id) ||
                !_awaitingCode.Contains(id) ||
                _beginningSignIn.Contains(id) ||
                !_completingSignIn.Add(id))
            {
                _loginErrors[id] =
                    "Start sign-in before submitting an authorization code.";
            }
            else
            {
                canComplete = true;
                _loginErrors[id] = null;
            }
        }

        RaiseChanged();
        if (!canComplete)
        {
            return;
        }

        try
        {
            await _auth[id]
                .CompleteSignInAsync(pastedCode, cancellationToken)
                .ConfigureAwait(false);
            lock (_stateGate)
            {
                _completingSignIn.Remove(id);
                _signingIn.Remove(id);
                _signInStartedAt.Remove(id);
                _awaitingCode.Remove(id);
                _loginErrors[id] = null;
            }

            RaiseChanged();
            await RefreshAsync(id, RefreshTrigger.Manual, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            lock (_stateGate)
            {
                _completingSignIn.Remove(id);
                _signingIn.Remove(id);
                _signInStartedAt.Remove(id);
                _awaitingCode.Remove(id);
                _loginErrors[id] = $"Sign-in failed: {FriendlyError(exception)}";
            }

            RaiseChanged();
        }
    }

    public void SignOut(AgentId id)
    {
        ThrowIfDisposed();
        try
        {
            _auth[id].SignOut();
        }
        catch (Exception exception)
        {
            lock (_stateGate)
            {
                _loginErrors[id] = $"Sign-out failed: {FriendlyError(exception)}";
            }

            RaiseChanged();
            return;
        }

        lock (_stateGate)
        {
            _sessionGenerations[id]++;
            _beginningSignIn.Remove(id);
            _completingSignIn.Remove(id);
            _signingIn.Remove(id);
            _signInStartedAt.Remove(id);
            _awaitingCode.Remove(id);
            _lastFetch[id] = null;
            _failures[id] = 0;
            _diagnostics[id] = null;
            _loginErrors[id] = null;
            _states[id] = AgentState.SignedOut;
            try
            {
                _settings.ClearLastSnapshot(id);
            }
            catch (Exception exception)
            {
                _loginErrors[id] =
                    "Signed out, but cached usage could not be removed: " +
                    FriendlyError(exception);
            }
        }

        RaiseChanged();
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _settings.Changed -= Settings_OnChanged;
        _lifetime.Cancel();
        lock (_stateGate)
        {
            foreach (var timer in _timers.Values)
            {
                timer.Cancel();
            }

            _timers.Clear();
        }

        await Task.Yield();
        // Refresh tasks may still be unwinding their finally blocks after the
        // cancellation. Leave the tiny semaphores for process teardown rather
        // than disposing one just before an in-flight task releases it.
        // The process is retiring and refresh tasks may still read the
        // cancellation flag while unwinding. Keep this small source alive so
        // those reads cannot race Dispose.
    }

    private AgentPresentation CreatePresentationLocked(AgentId id) =>
        new(
            AgentRegistry.Get(id),
            _states[id],
            _refreshing.GetValueOrDefault(id),
            _diagnostics.GetValueOrDefault(id),
            _loginErrors.GetValueOrDefault(id),
            _awaitingCode.Contains(id),
            _signingIn.Contains(id));

    private void ScheduleTimer(AgentId id, TimeSpan interval)
    {
        CancellationTokenSource timer;
        lock (_stateGate)
        {
            if (_disposed)
            {
                return;
            }

            if (_timers.Remove(id, out var previous))
            {
                previous.Cancel();
            }

            timer = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            _timers[id] = timer;
        }

        _ = RunTimerAsync(id, interval, timer);
    }

    private async Task RunTimerAsync(
        AgentId id,
        TimeSpan interval,
        CancellationTokenSource timer)
    {
        try
        {
            await Task.Delay(interval, timer.Token).ConfigureAwait(false);
            await RefreshAsync(id, RefreshTrigger.Timer, timer.Token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            lock (_stateGate)
            {
                if (_timers.TryGetValue(id, out var current) &&
                    ReferenceEquals(current, timer))
                {
                    _timers.Remove(id);
                }
            }

            // The timer task owns disposal. Replacers only cancel it, avoiding
            // a race with a continuation that still needs timer.Token.
            timer.Dispose();
        }
    }

    private static string FriendlyError(Exception exception)
    {
        if (exception is AggregateException aggregate)
        {
            exception = aggregate.GetBaseException();
        }

        return string.IsNullOrWhiteSpace(exception.Message)
            ? exception.GetType().Name
            : exception.Message;
    }

    private void Settings_OnChanged(object? sender, EventArgs eventArgs) =>
        RaiseChanged();

    private void RaiseChanged() => Changed?.Invoke(this, EventArgs.Empty);

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }
}
