using TokenStats.Core;

namespace TokenStats.App.Services;

public sealed record AgentPresentation(
    AgentDefinition Definition,
    AgentState State,
    AuthSessionState SessionState,
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
    private const string SignOutFailureDiagnostic =
        "TokenStats could not remove the saved credentials. The account remains connected.";
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
    private readonly Dictionary<AgentId, long> _signInAttemptGenerations = [];
    private readonly Dictionary<AgentId, DateTimeOffset?> _lastFetch = [];
    private readonly Dictionary<AgentId, int> _failures = [];
    private readonly Dictionary<AgentId, long> _sessionGenerations = [];
    private readonly Dictionary<AgentId, SemaphoreSlim> _refreshGates = [];
    private readonly Dictionary<AgentId, long> _pendingManualRefreshes = [];
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
                return _auth.Values.Count(
                    session =>
                        session.SessionState.Kind == AuthSessionStateKind.Valid);
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

                if (_auth[id].SessionState.Kind == AuthSessionStateKind.SignedOut)
                {
                    _states[id] = AgentState.SignedOut;
                }
            }
        }

        RaiseChanged();
        await RefreshAllAsync(RefreshTrigger.Startup, _lifetime.Token)
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
        CancellationToken cancellationToken = default,
        bool waitForExisting = false)
    {
        ThrowIfDisposed();
        var gate = _refreshGates[id];
        long? acquiredSessionGeneration = null;
        if (waitForExisting)
        {
            await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
            lock (_stateGate)
            {
                acquiredSessionGeneration = _sessionGenerations[id];
            }
        }
        else
        {
            cancellationToken.ThrowIfCancellationRequested();
            var acquired = false;
            lock (_stateGate)
            {
                if (trigger != RefreshTrigger.SignIn &&
                    _signingIn.Contains(id))
                {
                    if (trigger == RefreshTrigger.Manual)
                    {
                        // The accepted code exchange and its SignIn usage fetch
                        // satisfy this click. Never validate the old credential
                        // pair while its replacement is still in the browser.
                        _pendingManualRefreshes[id] = _sessionGenerations[id];
                    }

                    return;
                }

                acquired = gate.Wait(0);
                if (acquired)
                {
                    // Linearize refresh ownership with BeginSignIn, which uses
                    // this same lock to advance the credential generation.
                    acquiredSessionGeneration = _sessionGenerations[id];
                }
                if (!acquired &&
                    trigger == RefreshTrigger.Manual &&
                    _auth[id].SessionState.Kind is not (
                        AuthSessionStateKind.SignedOut or
                        AuthSessionStateKind.ReauthenticationRequired))
                {
                    // Bind the pending click to the credential generation that
                    // existed when it was made. An old timer must not replay it
                    // against replacement credentials after reconnect.
                    _pendingManualRefreshes[id] = _sessionGenerations[id];
                }
            }

            if (!acquired)
            {
                return;
            }
        }

        long? refreshGeneration = null;
        try
        {
            var authSession = _auth[id];
            var currentSessionState = authSession.SessionState;
            if (currentSessionState.Kind ==
                AuthSessionStateKind.ReauthenticationRequired)
            {
                lock (_stateGate)
                {
                    _diagnostics[id] = currentSessionState.Diagnostic;
                    _states[id] = AgentStateReducer.Reduce(
                        _states[id],
                        new AgentEvent(AgentEventKind.FetchFailed));
                }

                RaiseChanged();
                // Quarantined credentials are retained for explicit user
                // replacement, but timers must not keep presenting them to
                // either the token or usage endpoint.
                CancelTimer(id);
                return;
            }

            DateTimeOffset? lastFetch;
            int failures;
            long sessionGeneration;
            lock (_stateGate)
            {
                lastFetch = _lastFetch.GetValueOrDefault(id);
                failures = _failures.GetValueOrDefault(id);
                sessionGeneration = acquiredSessionGeneration ??
                    _sessionGenerations[id];
                refreshGeneration = sessionGeneration;
            }

            if (!IsCurrentSessionGeneration(id, sessionGeneration))
            {
                return;
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

            if (!authSession.IsSignedIn)
            {
                var sessionState = authSession.SessionState;
                var retryInterval = decision.NextInterval;
                lock (_stateGate)
                {
                    switch (sessionState.Kind)
                    {
                    case AuthSessionStateKind.ReauthenticationRequired:
                        _diagnostics[id] = sessionState.Diagnostic;
                        _states[id] = AgentStateReducer.Reduce(
                            _states[id],
                            new AgentEvent(AgentEventKind.FetchFailed));
                        break;
                    case AuthSessionStateKind.TemporarilyUnverifiable:
                    case AuthSessionStateKind.Checking:
                        _failures[id] = _failures.GetValueOrDefault(id) + 1;
                        _diagnostics[id] = sessionState.Diagnostic;
                        _states[id] = AgentStateReducer.Reduce(
                            _states[id],
                            new AgentEvent(AgentEventKind.FetchFailed));
                        retryInterval = RefreshPolicy.Decide(
                            RefreshTrigger.Timer,
                            _lastFetch.GetValueOrDefault(id),
                            DateTimeOffset.Now,
                            _failures[id]).NextInterval;
                        break;
                    default:
                        _states[id] = AgentState.SignedOut;
                        break;
                    }
                }

                RaiseChanged();
                if (sessionState.Kind !=
                    AuthSessionStateKind.ReauthenticationRequired)
                {
                    ScheduleTimer(id, retryInterval);
                }

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
                var proactive = authSession as IProactiveAuthSession;
                var forceAttempted = false;
                if (proactive is not null &&
                    trigger is RefreshTrigger.Startup or RefreshTrigger.Manual)
                {
                    Task<AuthSessionState>? validationTask = null;
                    lock (_stateGate)
                    {
                        if (_sessionGenerations[id] == sessionGeneration)
                        {
                            // Invoking the async method while holding the
                            // generation lock lets the auth session capture its
                            // own revision before a reconnect can advance it.
                            validationTask = proactive.ForceValidateSessionAsync(
                                linked.Token);
                        }
                    }
                    if (validationTask is null)
                    {
                        return;
                    }

                    forceAttempted = true;
                    RaiseChanged();
                    var validation = await validationTask.ConfigureAwait(false);
                    if (!IsCurrentSessionGeneration(id, sessionGeneration))
                    {
                        return;
                    }

                    RaiseChanged();
                    if (validation.Kind != AuthSessionStateKind.Valid)
                    {
                        throw new InvalidOperationException(
                            validation.Diagnostic ??
                            "The session could not be verified.");
                    }
                }

                IReadOnlyList<UsageWindow> windows;
                try
                {
                    Task<IReadOnlyList<UsageWindow>>? usageTask = null;
                    lock (_stateGate)
                    {
                        if (_sessionGenerations[id] == sessionGeneration)
                        {
                            usageTask = _providers[id].FetchUsageAsync(linked.Token);
                        }
                    }
                    if (usageTask is null)
                    {
                        return;
                    }

                    windows = await usageTask.ConfigureAwait(false);
                    if (!IsCurrentSessionGeneration(id, sessionGeneration))
                    {
                        return;
                    }
                }
                catch (UsageException exception) when (
                    exception.StatusCode == 401 && proactive is not null)
                {
                    if (!IsCurrentSessionGeneration(id, sessionGeneration))
                    {
                        return;
                    }

                    if (forceAttempted)
                    {
                        var applied = ApplyAuthMutationIfCurrent(
                            id,
                            sessionGeneration,
                            () =>
                            {
                                if (authSession.SessionState.Kind ==
                                    AuthSessionStateKind.Valid)
                                {
                                    proactive.RequireReauthentication(
                                        OAuthRefreshFailureReason.Unauthorized,
                                        "The refreshed Codex session was rejected by the usage service. Sign in again.");
                                }
                            });
                        if (!applied)
                        {
                            return;
                        }

                        throw new InvalidOperationException(
                            authSession.SessionState.Diagnostic ??
                            "The Codex session could not access usage.");
                    }

                    Task<AuthSessionState>? validationTask = null;
                    lock (_stateGate)
                    {
                        if (_sessionGenerations[id] == sessionGeneration)
                        {
                            validationTask = proactive.ForceValidateSessionAsync(
                                linked.Token);
                        }
                    }
                    if (validationTask is null)
                    {
                        return;
                    }

                    forceAttempted = true;
                    RaiseChanged();
                    var validation = await validationTask.ConfigureAwait(false);
                    if (!IsCurrentSessionGeneration(id, sessionGeneration))
                    {
                        return;
                    }

                    RaiseChanged();
                    if (validation.Kind != AuthSessionStateKind.Valid)
                    {
                        throw new InvalidOperationException(
                            validation.Diagnostic ??
                            "The session could not be verified.");
                    }

                    // A successful forced refresh is the session proof. A
                    // non-401 retry failure only stales usage; another 401
                    // means the refreshed session is unusable and quarantined.
                    try
                    {
                        Task<IReadOnlyList<UsageWindow>>? retryTask = null;
                        lock (_stateGate)
                        {
                            if (_sessionGenerations[id] == sessionGeneration)
                            {
                                retryTask = _providers[id].FetchUsageAsync(
                                    linked.Token);
                            }
                        }
                        if (retryTask is null)
                        {
                            return;
                        }

                        windows = await retryTask.ConfigureAwait(false);
                        if (!IsCurrentSessionGeneration(id, sessionGeneration))
                        {
                            return;
                        }
                    }
                    catch (UsageException retryException) when (
                        retryException.StatusCode == 401)
                    {
                        if (!ApplyAuthMutationIfCurrent(
                                id,
                                sessionGeneration,
                                () => proactive.RequireReauthentication(
                                    OAuthRefreshFailureReason.Unauthorized,
                                    "The refreshed Codex session was rejected by the usage service. Sign in again.")))
                        {
                            return;
                        }

                        throw new InvalidOperationException(
                            authSession.SessionState.Diagnostic ??
                            "The Codex session could not access usage.",
                            retryException);
                    }
                }

                if (!authSession.IsSignedIn)
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
                        authSession.MarkUsageSucceeded(now);
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
                var friendly = FriendlyError(exception);
                lock (_stateGate)
                {
                    if (_sessionGenerations[id] != sessionGeneration)
                    {
                        return;
                    }

                    authSession.MarkUsageFailed(friendly);
                    var sessionState = authSession.SessionState;
                    if (sessionState.Kind == AuthSessionStateKind.SignedOut)
                    {
                        return;
                    }

                    _failures[id] = _failures.GetValueOrDefault(id) + 1;
                    // Keep the usage failure separate from an authentication
                    // diagnostic (for example, a rotated-token persistence
                    // warning). CreatePresentationLocked combines both.
                    _diagnostics[id] = friendly;
                    _states[id] = AgentStateReducer.Reduce(
                        _states[id],
                        new AgentEvent(AgentEventKind.FetchFailed));
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

            if (!IsCurrentSessionGeneration(id, sessionGeneration))
            {
                return;
            }

            if (authSession.SessionState.Kind ==
                AuthSessionStateKind.ReauthenticationRequired)
            {
                CancelTimer(id);
                return;
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
            var replayManual = false;
            lock (_stateGate)
            {
                var matchedPendingManual = false;
                if (refreshGeneration is { } completedGeneration &&
                    _pendingManualRefreshes.TryGetValue(
                        id,
                        out var pendingGeneration) &&
                    pendingGeneration == completedGeneration)
                {
                    _pendingManualRefreshes.Remove(id);
                    matchedPendingManual = true;
                }

                if (matchedPendingManual &&
                    trigger is not (RefreshTrigger.Startup or RefreshTrigger.Manual) &&
                    !_disposed)
                {
                    replayManual = true;
                }

                // Manual enqueue and zero-time acquisition use this same lock,
                // so no caller can slip into the release/removal window and
                // leave a pending validation stranded or incorrectly consumed.
                gate.Release();
            }

            if (replayManual)
            {
                _ = ReplayPendingManualRefreshAsync(id);
            }
        }
    }

    public async Task BeginSignInAsync(
        AgentId id,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        var definition = AgentRegistry.Get(id);
        var canBegin = false;
        long attemptGeneration = -1;
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
                attemptGeneration = ++_sessionGenerations[id];
                _pendingManualRefreshes.Remove(id);
                _signInAttemptGenerations[id] = attemptGeneration;
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
            Task beginTask;
            lock (_stateGate)
            {
                if (_sessionGenerations[id] != attemptGeneration)
                {
                    return;
                }

                beginTask = _auth[id].BeginSignInAsync(cancellationToken);
            }

            await beginTask.ConfigureAwait(false);
            var staleAttempt = false;
            lock (_stateGate)
            {
                staleAttempt = _sessionGenerations[id] != attemptGeneration ||
                    _signInAttemptGenerations.GetValueOrDefault(id, -1) !=
                    attemptGeneration;
                if (!staleAttempt)
                {
                    _beginningSignIn.Remove(id);
                    _loginErrors[id] = null;
                    if (definition.SignInStyle == SignInStyle.SelfCompleting)
                    {
                        if (_pendingManualRefreshes.GetValueOrDefault(id, -1) ==
                            attemptGeneration)
                        {
                            _pendingManualRefreshes.Remove(id);
                        }
                        _signInAttemptGenerations.Remove(id);
                        _lastFetch[id] = null;
                        _failures[id] = 0;
                        _diagnostics[id] = null;
                        _signingIn.Remove(id);
                        _signInStartedAt.Remove(id);
                        _awaitingCode.Remove(id);
                    }
                }
            }

            if (staleAttempt)
            {
                return;
            }

            RaiseChanged();
            if (definition.SignInStyle == SignInStyle.SelfCompleting)
            {
                await RefreshAsync(
                        id,
                        RefreshTrigger.SignIn,
                        cancellationToken,
                        waitForExisting: true)
                    .ConfigureAwait(false);
            }
        }
        catch (Exception exception)
        {
            var staleAttempt = false;
            lock (_stateGate)
            {
                staleAttempt = _sessionGenerations[id] != attemptGeneration ||
                    _signInAttemptGenerations.GetValueOrDefault(id, -1) !=
                    attemptGeneration;
                if (!staleAttempt)
                {
                    if (_pendingManualRefreshes.GetValueOrDefault(id, -1) ==
                        attemptGeneration)
                    {
                        _pendingManualRefreshes.Remove(id);
                    }
                    _signInAttemptGenerations.Remove(id);
                    _beginningSignIn.Remove(id);
                    _signingIn.Remove(id);
                    _signInStartedAt.Remove(id);
                    _awaitingCode.Remove(id);
                    _loginErrors[id] = $"Sign-in failed: {FriendlyError(exception)}";
                }
            }

            if (!staleAttempt)
            {
                RaiseChanged();
            }
        }
    }

    public async Task CompleteSignInAsync(
        AgentId id,
        string pastedCode,
        CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        var canComplete = false;
        long attemptGeneration = -1;
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
                attemptGeneration = _signInAttemptGenerations.GetValueOrDefault(
                    id,
                    -1);
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
            Task completionTask;
            lock (_stateGate)
            {
                if (_sessionGenerations[id] != attemptGeneration)
                {
                    return;
                }

                completionTask = _auth[id].CompleteSignInAsync(
                    pastedCode,
                    cancellationToken);
            }

            await completionTask.ConfigureAwait(false);
            var staleAttempt = false;
            lock (_stateGate)
            {
                staleAttempt = _sessionGenerations[id] != attemptGeneration ||
                    _signInAttemptGenerations.GetValueOrDefault(id, -1) !=
                    attemptGeneration;
                if (!staleAttempt)
                {
                    if (_pendingManualRefreshes.GetValueOrDefault(id, -1) ==
                        attemptGeneration)
                    {
                        _pendingManualRefreshes.Remove(id);
                    }
                    _signInAttemptGenerations.Remove(id);
                    _lastFetch[id] = null;
                    _failures[id] = 0;
                    _diagnostics[id] = null;
                    _completingSignIn.Remove(id);
                    _signingIn.Remove(id);
                    _signInStartedAt.Remove(id);
                    _awaitingCode.Remove(id);
                    _loginErrors[id] = null;
                }
            }

            if (staleAttempt)
            {
                return;
            }

            RaiseChanged();
            await RefreshAsync(
                    id,
                    RefreshTrigger.SignIn,
                    cancellationToken,
                    waitForExisting: true)
                .ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            var staleAttempt = false;
            lock (_stateGate)
            {
                staleAttempt = _sessionGenerations[id] != attemptGeneration ||
                    _signInAttemptGenerations.GetValueOrDefault(id, -1) !=
                    attemptGeneration;
                if (!staleAttempt)
                {
                    if (_pendingManualRefreshes.GetValueOrDefault(id, -1) ==
                        attemptGeneration)
                    {
                        _pendingManualRefreshes.Remove(id);
                    }
                    _signInAttemptGenerations.Remove(id);
                    _completingSignIn.Remove(id);
                    _signingIn.Remove(id);
                    _signInStartedAt.Remove(id);
                    _awaitingCode.Remove(id);
                    _loginErrors[id] = $"Sign-in failed: {FriendlyError(exception)}";
                }
            }

            if (!staleAttempt)
            {
                RaiseChanged();
            }
        }
    }

    public void SignOut(AgentId id)
    {
        ThrowIfDisposed();
        var signOutSucceeded = false;
        lock (_stateGate)
        {
            // Advance coordinator ownership and clear pending sign-in state in
            // the same critical section as auth.SignOut. A late BeginSignIn can
            // therefore only linearize before this clear (and be invalidated by
            // the auth generation) or after it as an intentional new login.
            _sessionGenerations[id]++;
            _signInAttemptGenerations.Remove(id);
            _pendingManualRefreshes.Remove(id);
            _beginningSignIn.Remove(id);
            _completingSignIn.Remove(id);
            _signingIn.Remove(id);
            _signInStartedAt.Remove(id);
            _awaitingCode.Remove(id);
            try
            {
                _auth[id].SignOut();
                signOutSucceeded = true;
            }
            catch (Exception)
            {
                // Durable credential removal failed, so the account remains
                // owned by this coordinator generation. Do not clear usage or
                // present SignedOut. Keep the backend exception out of UI and
                // arrange a later refresh to reconcile the retained session.
                _auth[id].MarkUsageFailed(SignOutFailureDiagnostic);
                _refreshing[id] = false;
                _diagnostics[id] = SignOutFailureDiagnostic;
                _loginErrors[id] = $"Sign-out failed. {SignOutFailureDiagnostic}";
                var failedState = AgentStateReducer.Reduce(
                    _states[id],
                    new AgentEvent(AgentEventKind.FetchFailed));
                _states[id] = failedState.Kind == AgentStateKind.SignedOut
                    ? AgentState.Loading
                    : failedState;
            }

            if (signOutSucceeded)
            {
                _lastFetch[id] = null;
                _failures[id] = 0;
                _diagnostics[id] = null;
                _loginErrors[id] = null;
                _refreshing[id] = false;
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
        }

        RaiseChanged();
        if (signOutSucceeded)
        {
            CancelTimer(id);
        }
        else
        {
            ScheduleTimer(id, RefreshPolicy.BaseInterval);
        }
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
            _pendingManualRefreshes.Clear();
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
            _auth[id].SessionState,
            _refreshing.GetValueOrDefault(id),
            CombineDiagnostics(
                _auth[id].SessionState.Diagnostic,
                _diagnostics.GetValueOrDefault(id)),
            _loginErrors.GetValueOrDefault(id),
            _awaitingCode.Contains(id),
            _signingIn.Contains(id));

    private static string? CombineDiagnostics(string? session, string? usage)
    {
        if (string.IsNullOrWhiteSpace(session))
        {
            return usage;
        }

        if (string.IsNullOrWhiteSpace(usage) ||
            string.Equals(session, usage, StringComparison.Ordinal))
        {
            return session;
        }

        return $"{session}{Environment.NewLine}{usage}";
    }

    private bool IsCurrentSessionGeneration(AgentId id, long generation)
    {
        lock (_stateGate)
        {
            return _sessionGenerations[id] == generation;
        }
    }

    private bool ApplyAuthMutationIfCurrent(
        AgentId id,
        long generation,
        Action mutation)
    {
        lock (_stateGate)
        {
            if (_sessionGenerations[id] != generation)
            {
                return false;
            }

            mutation();
            return true;
        }
    }

    private async Task ReplayPendingManualRefreshAsync(AgentId id)
    {
        try
        {
            await RefreshAsync(id, RefreshTrigger.Manual, _lifetime.Token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
        catch (ObjectDisposedException)
        {
        }
    }

    private void CancelTimer(AgentId id)
    {
        lock (_stateGate)
        {
            if (_timers.Remove(id, out var timer))
            {
                timer.Cancel();
            }
        }
    }

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
