using System.Diagnostics;
using System.Net.Http;
using TokenStats.Core;

namespace TokenStats.App.Infrastructure;

internal static class CredentialSessionPresentation
{
    public const string UnavailableDiagnostic =
        "TokenStats could not read the saved credentials right now.";

    public static AuthSessionState Initial(CredentialPresence presence) =>
        presence switch
        {
            CredentialPresence.Present => AuthSessionState.Checking(),
            CredentialPresence.Absent => AuthSessionState.SignedOut,
            CredentialPresence.TemporarilyUnavailable =>
                AuthSessionState.TemporarilyUnverifiable(
                    null,
                    UnavailableDiagnostic),
            _ => AuthSessionState.TemporarilyUnverifiable(
                null,
                UnavailableDiagnostic),
        };

    public static AuthSessionState Reconcile(
        CredentialPresence presence,
        AuthSessionState current) => presence switch
        {
            CredentialPresence.Present
                when current.Kind == AuthSessionStateKind.SignedOut ||
                     current.Kind == AuthSessionStateKind.TemporarilyUnverifiable &&
                     string.Equals(
                         current.Diagnostic,
                         UnavailableDiagnostic,
                         StringComparison.Ordinal) =>
                AuthSessionState.Checking(current.LastValidatedAt),
            CredentialPresence.Absent => AuthSessionState.SignedOut,
            CredentialPresence.TemporarilyUnavailable
                when current.Kind !=
                    AuthSessionStateKind.ReauthenticationRequired =>
                AuthSessionState.TemporarilyUnverifiable(
                    current.LastValidatedAt,
                    UnavailableDiagnostic),
            _ => current,
        };
}

public sealed class ClaudeAuthSession : IAgentAuthSession
{
    private readonly AgentTokenCache _cache;
    private readonly OAuthHttpClient _client;
    private readonly object _pendingGate = new();
    private readonly object _sessionStateGate = new();
    private (
        Pkce Pkce,
        string State,
        int CredentialGeneration,
        int SessionGeneration)? _pending;
    private AuthSessionState _sessionState;
    private int _sessionGeneration;

    public ClaudeAuthSession(
        ITokenStore store,
        OAuthHttpClient client,
        Func<DateTimeOffset>? now = null)
    {
        _client = client;
        _cache = new AgentTokenCache(
            store,
            (expired, cancellationToken) =>
                client.RefreshClaudeCodeAsync(expired.RefreshToken, cancellationToken),
            now);
        _sessionState = CredentialSessionPresentation.Initial(
            _cache.CredentialStatus);
    }

    public bool IsSignedIn => ReconcileCredentialPresence();
    public string? AccountId => null;
    public AuthSessionState SessionState
    {
        get
        {
            lock (_sessionStateGate)
            {
                return _sessionState;
            }
        }
    }

    public Task<string> ValidAccessTokenAsync(
        CancellationToken cancellationToken = default) =>
        _cache.ValidAccessTokenAsync(cancellationToken);

    public Task BeginSignInAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var credentialGeneration = _cache.CaptureCredentialGeneration();
        int sessionGeneration;
        lock (_sessionStateGate)
        {
            sessionGeneration = ++_sessionGeneration;
        }

        var pending = (
            Pkce: OAuthHelpers.MakePkce(),
            State: OAuthHelpers.MakeState(),
            CredentialGeneration: credentialGeneration,
            SessionGeneration: sessionGeneration);
        lock (_pendingGate)
        {
            _pending = pending;
        }

        try
        {
            BrowserLauncher.Open(ClaudeOAuthFlow.AuthorizeUrl(pending.Pkce, pending.State));
            return Task.CompletedTask;
        }
        catch
        {
            lock (_pendingGate)
            {
                _pending = null;
            }

            throw;
        }
    }

    public async Task CompleteSignInAsync(
        string pastedCode,
        CancellationToken cancellationToken = default)
    {
        (
            Pkce Pkce,
            string State,
            int CredentialGeneration,
            int SessionGeneration)? pending;
        lock (_pendingGate)
        {
            pending = _pending;
        }

        if (pending is null)
        {
            throw UsageException.NotSignedIn();
        }

        var split = OAuthHelpers.SplitPastedCode(pastedCode);
        if (string.IsNullOrWhiteSpace(split.Code))
        {
            throw new InvalidOperationException("Paste the authorization code from the browser.");
        }

        if (split.State is { Length: > 0 } returnedState &&
            !string.Equals(returnedState, pending.Value.State, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "State mismatch — possible interference; try again.");
        }

        var tokens = await _client.ExchangeClaudeCodeAsync(
            split.Code,
            pending.Value.Pkce.Verifier,
            pending.Value.State,
            cancellationToken).ConfigureAwait(false);
        await _cache.AdoptAsync(
                tokens,
                pending.Value.CredentialGeneration,
                cancellationToken)
            .ConfigureAwait(false);
        lock (_sessionStateGate)
        {
            if (_sessionGeneration != pending.Value.SessionGeneration)
            {
                throw UsageException.NotSignedIn();
            }

            _sessionState = AuthSessionState.Checking();
        }
        lock (_pendingGate)
        {
            _pending = null;
        }
    }

    public void MarkUsageSucceeded(DateTimeOffset validatedAt)
    {
        lock (_sessionStateGate)
        {
            if (_sessionState.Kind != AuthSessionStateKind.SignedOut &&
                IsSignedIn)
            {
                _sessionState = AuthSessionState.Valid(validatedAt);
            }
        }
    }

    public void MarkUsageFailed(string diagnostic)
    {
        lock (_sessionStateGate)
        {
            if (_sessionState.Kind == AuthSessionStateKind.Checking &&
                IsSignedIn)
            {
                _sessionState = AuthSessionState.TemporarilyUnverifiable(
                    _sessionState.LastValidatedAt,
                    diagnostic);
            }
        }
    }

    public void SignOut()
    {
        lock (_sessionStateGate)
        {
            _cache.SignOut();
            _sessionGeneration++;
            _sessionState = AuthSessionState.SignedOut;
        }
        lock (_pendingGate)
        {
            _pending = null;
        }
    }

    private void SetSessionState(AuthSessionState state)
    {
        lock (_sessionStateGate)
        {
            _sessionState = state;
        }
    }

    private bool ReconcileCredentialPresence()
    {
        var presence = _cache.CredentialStatus;
        lock (_sessionStateGate)
        {
            _sessionState = CredentialSessionPresentation.Reconcile(
                presence,
                _sessionState);
        }

        return presence == CredentialPresence.Present;
    }
}

public sealed class CodexAuthSession : IAgentAuthSession, IProactiveAuthSession
{
    private readonly AgentTokenCache _cache;
    private readonly OAuthHttpClient _client;
    private readonly Func<DateTimeOffset> _now;
    private readonly object _sessionStateGate = new();
    private AuthSessionState _sessionState;
    private int _sessionGeneration;

    public CodexAuthSession(
        ITokenStore store,
        OAuthHttpClient client,
        Func<DateTimeOffset>? now = null)
    {
        _client = client;
        _now = now ?? (() => DateTimeOffset.Now);
        _cache = new AgentTokenCache(
            store,
            (expired, cancellationToken) =>
                client.RefreshCodexAsync(expired, cancellationToken),
            now);
        _sessionState = CredentialSessionPresentation.Initial(
            _cache.CredentialStatus);
    }

    public bool IsSignedIn => ReconcileCredentialPresence();
    public string? AccountId => _cache.AccountId;
    public AuthSessionState SessionState
    {
        get
        {
            lock (_sessionStateGate)
            {
                return _sessionState;
            }
        }
    }

    public async Task<string> ValidAccessTokenAsync(
        CancellationToken cancellationToken = default)
    {
        int generation;
        lock (_sessionStateGate)
        {
            if (_sessionState.Kind ==
                AuthSessionStateKind.ReauthenticationRequired)
            {
                throw UsageException.NotSignedIn();
            }

            generation = _sessionGeneration;
        }

        var refreshRequired = _cache.Tokens?.IsExpired(_now()) == true;
        try
        {
            var token = await _cache.ValidAccessTokenAsync(cancellationToken)
                .ConfigureAwait(false);
            if (refreshRequired)
            {
                SetSessionStateIfCurrent(
                    generation,
                    AuthSessionState.Valid(_now()));
            }

            return token;
        }
        catch (TokenPersistenceException exception)
        {
            SetSessionStateIfCurrent(
                generation,
                AuthSessionState.Valid(_now(), exception.Message));
            if (_cache.Tokens is { } refreshed)
            {
                return refreshed.AccessToken;
            }

            throw;
        }
        catch (RefreshedAccessTokenUnavailableException exception)
        {
            // Refresh acceptance proves the grant is valid, but there is no
            // bearer that may be sent to Usage yet. Preserve the adopted
            // rotation, expose a safe diagnostic, and let the coordinator stale
            // Usage until a later refresh returns a usable access token.
            SetSessionStateIfCurrent(
                generation,
                AuthSessionState.Valid(_now(), exception.Message));
            throw;
        }
        catch (OAuthRefreshException exception) when (exception.IsTerminal)
        {
            RequireReauthenticationIfCurrent(generation, exception);
            throw;
        }
        catch (OperationCanceledException) when (
            cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (refreshRequired)
        {
            SetSessionStateIfCurrent(
                generation,
                AuthSessionState.TemporarilyUnverifiable(
                    SessionState.LastValidatedAt,
                    TransientValidationDiagnostic(exception)));
            throw;
        }
    }

    public async Task<AuthSessionState> ForceValidateSessionAsync(
        CancellationToken cancellationToken = default)
    {
        AuthSessionState previous;
        int generation;
        lock (_sessionStateGate)
        {
            if (!IsSignedIn ||
                _sessionState.Kind is AuthSessionStateKind.SignedOut or
                    AuthSessionStateKind.ReauthenticationRequired)
            {
                return _sessionState;
            }

            previous = _sessionState;
            generation = _sessionGeneration;
            _sessionState = AuthSessionState.Checking(previous.LastValidatedAt);
        }

        try
        {
            _ = await _cache.ForceRefreshAccessTokenAsync(cancellationToken)
                .ConfigureAwait(false);
            SetSessionStateIfCurrent(
                generation,
                AuthSessionState.Valid(_now()));
            return SessionState;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            SetSessionStateIfCurrent(generation, previous);

            throw;
        }
        catch (TokenPersistenceException exception)
        {
            // The server accepted and rotated the token, so the online session
            // is valid even though it may not survive process restart.
            SetSessionStateIfCurrent(
                generation,
                AuthSessionState.Valid(_now(), exception.Message));
            return SessionState;
        }
        catch (RefreshedAccessTokenUnavailableException exception)
        {
            SetSessionStateIfCurrent(
                generation,
                AuthSessionState.Valid(_now(), exception.Message));
            throw;
        }
        catch (OAuthRefreshException exception) when (exception.IsTerminal)
        {
            RequireReauthenticationIfCurrent(generation, exception);
            return SessionState;
        }
        catch (Exception exception)
        {
            SetSessionStateIfCurrent(
                generation,
                AuthSessionState.TemporarilyUnverifiable(
                    previous.LastValidatedAt,
                    TransientValidationDiagnostic(exception)));
            return SessionState;
        }
    }

    public async Task BeginSignInAsync(CancellationToken cancellationToken = default)
    {
        var credentialGeneration = _cache.CaptureCredentialGeneration();
        int sessionGeneration;
        lock (_sessionStateGate)
        {
            sessionGeneration = ++_sessionGeneration;
        }
        await using var listener = new LoopbackAuthListener();
        var port = await listener.StartAsync(cancellationToken).ConfigureAwait(false);
        var redirectUri = CodexOAuthFlow.RedirectUri(port);
        var pkce = OAuthHelpers.MakePkce();
        var state = OAuthHelpers.MakeState();

        BrowserLauncher.Open(CodexOAuthFlow.AuthorizeUrl(pkce, state, redirectUri));
        var callback = await listener.WaitForCallbackAsync(state, cancellationToken)
            .ConfigureAwait(false);

        var tokens = await _client.ExchangeCodexAsync(
            callback.Code,
            pkce.Verifier,
            redirectUri,
            cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(tokens.RefreshToken))
        {
            throw new InvalidOperationException(
                "Sign-in did not return a refresh token; cannot stay signed in.");
        }

        await _cache.AdoptAsync(
                tokens,
                credentialGeneration,
                cancellationToken)
            .ConfigureAwait(false);
        lock (_sessionStateGate)
        {
            if (_sessionGeneration != sessionGeneration)
            {
                throw UsageException.NotSignedIn();
            }

            // Fresh credentials start a new validation epoch. Any force check
            // that began against the previous pair during the browser flow can
            // no longer publish a late terminal/transient state over this login.
            _sessionGeneration++;
            // The authorization-code exchange has just been accepted and
            // returned a fresh refresh token. That server response is already
            // authoritative session proof, so do not immediately rotate the
            // newly issued grant again merely to leave Checking.
            _sessionState = AuthSessionState.Valid(_now());
        }
    }

    public Task CompleteSignInAsync(
        string pastedCode,
        CancellationToken cancellationToken = default) =>
        Task.FromException(
            new InvalidOperationException(
                "Codex completes sign-in automatically in the browser."));

    public void MarkUsageSucceeded(DateTimeOffset validatedAt)
    {
        // A usage response proves that the current access token works, not that
        // the independently stored refresh token remains refreshable. Forced
        // refresh success is the Codex validity boundary.
    }

    public void MarkUsageFailed(string diagnostic)
    {
        lock (_sessionStateGate)
        {
            if (_sessionState.Kind == AuthSessionStateKind.Checking &&
                IsSignedIn)
            {
                _sessionState = AuthSessionState.TemporarilyUnverifiable(
                    _sessionState.LastValidatedAt,
                    diagnostic);
            }
        }
    }

    public void RequireReauthentication(
        OAuthRefreshFailureReason reason,
        string diagnostic)
    {
        lock (_sessionStateGate)
        {
            if (_sessionState.Kind != AuthSessionStateKind.SignedOut)
            {
                _sessionState = AuthSessionState.ReauthenticationRequired(
                    reason,
                    diagnostic);
            }
        }
    }

    public void SignOut()
    {
        lock (_sessionStateGate)
        {
            _cache.SignOut();
            _sessionGeneration++;
            _sessionState = AuthSessionState.SignedOut;
        }
    }

    private void SetSessionStateIfCurrent(
        int generation,
        AuthSessionState state)
    {
        lock (_sessionStateGate)
        {
            if (_sessionGeneration == generation &&
                _sessionState.Kind is not (
                    AuthSessionStateKind.SignedOut or
                    AuthSessionStateKind.ReauthenticationRequired))
            {
                _sessionState = state;
            }
        }
    }

    private void RequireReauthenticationIfCurrent(
        int generation,
        OAuthRefreshException exception)
    {
        lock (_sessionStateGate)
        {
            if (_sessionGeneration == generation &&
                _sessionState.Kind != AuthSessionStateKind.SignedOut)
            {
                _sessionState = AuthSessionState.ReauthenticationRequired(
                    exception.Reason,
                    ReauthenticationDiagnostic(exception));
            }
        }
    }

    private static string ReauthenticationDiagnostic(
        OAuthRefreshException exception) =>
        exception.Reason switch
        {
            OAuthRefreshFailureReason.Expired =>
                "The Codex session expired. Sign in again.",
            OAuthRefreshFailureReason.Reused =>
                "The Codex refresh token was already used. Sign in again.",
            OAuthRefreshFailureReason.Revoked =>
                "The Codex session was revoked. Sign in again.",
            OAuthRefreshFailureReason.InvalidGrant =>
                "The Codex session is no longer refreshable. Sign in again.",
            _ => "The Codex session was rejected. Sign in again.",
        };

    private static string TransientValidationDiagnostic(Exception exception) =>
        exception switch
        {
            OAuthRefreshException refresh =>
                $"Codex could not verify the session (HTTP {refresh.StatusCode}).",
            TimeoutException => "Codex session verification timed out.",
            OperationCanceledException => "Codex session verification timed out.",
            HttpRequestException => "Codex could not reach the authentication service.",
            _ => "Codex could not verify the session right now.",
        };

    private bool ReconcileCredentialPresence()
    {
        var presence = _cache.CredentialStatus;
        lock (_sessionStateGate)
        {
            _sessionState = CredentialSessionPresentation.Reconcile(
                presence,
                _sessionState);
        }

        return presence == CredentialPresence.Present;
    }
}

public sealed class CursorAuthSession : IAgentAuthSession
{
    private readonly AgentTokenCache _cache;
    private readonly OAuthHttpClient _client;
    private readonly object _sessionStateGate = new();
    private AuthSessionState _sessionState;
    private int _sessionGeneration;

    public CursorAuthSession(
        ITokenStore store,
        OAuthHttpClient client,
        Func<DateTimeOffset>? now = null)
    {
        _client = client;
        _cache = new AgentTokenCache(
            store,
            (expired, cancellationToken) =>
                client.RefreshCursorAsync(expired, cancellationToken),
            now);
        _sessionState = CredentialSessionPresentation.Initial(
            _cache.CredentialStatus);
    }

    public bool IsSignedIn => ReconcileCredentialPresence();
    public string? AccountId => null;
    public AuthSessionState SessionState
    {
        get
        {
            lock (_sessionStateGate)
            {
                return _sessionState;
            }
        }
    }

    public Task<string> ValidAccessTokenAsync(
        CancellationToken cancellationToken = default) =>
        _cache.ValidAccessTokenAsync(cancellationToken);

    public async Task BeginSignInAsync(
        CancellationToken cancellationToken = default)
    {
        var credentialGeneration = _cache.CaptureCredentialGeneration();
        int sessionGeneration;
        lock (_sessionStateGate)
        {
            sessionGeneration = ++_sessionGeneration;
        }
        var pkce = OAuthHelpers.MakePkce();
        var uuid = Guid.NewGuid().ToString();
        BrowserLauncher.Open(CursorOAuthFlow.AuthorizeUrl(pkce, uuid));
        var tokens = await _client.WaitForCursorLoginAsync(
                pkce,
                uuid,
                cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(tokens.RefreshToken))
        {
            throw new InvalidOperationException(
                "Sign-in did not return a refresh token; cannot stay signed in.");
        }

        await _cache.AdoptAsync(
                tokens,
                credentialGeneration,
                cancellationToken)
            .ConfigureAwait(false);
        lock (_sessionStateGate)
        {
            if (_sessionGeneration != sessionGeneration)
            {
                throw UsageException.NotSignedIn();
            }

            _sessionState = AuthSessionState.Checking();
        }
    }

    public Task CompleteSignInAsync(
        string pastedCode,
        CancellationToken cancellationToken = default) =>
        Task.FromException(
            new InvalidOperationException(
                "Cursor completes sign-in automatically in the browser."));

    public void MarkUsageSucceeded(DateTimeOffset validatedAt)
    {
        lock (_sessionStateGate)
        {
            if (_sessionState.Kind != AuthSessionStateKind.SignedOut &&
                IsSignedIn)
            {
                _sessionState = AuthSessionState.Valid(validatedAt);
            }
        }
    }

    public void MarkUsageFailed(string diagnostic)
    {
        lock (_sessionStateGate)
        {
            if (_sessionState.Kind == AuthSessionStateKind.Checking &&
                IsSignedIn)
            {
                _sessionState = AuthSessionState.TemporarilyUnverifiable(
                    _sessionState.LastValidatedAt,
                    diagnostic);
            }
        }
    }

    public void SignOut()
    {
        lock (_sessionStateGate)
        {
            _cache.SignOut();
            _sessionGeneration++;
            _sessionState = AuthSessionState.SignedOut;
        }
    }

    private void SetSessionState(AuthSessionState state)
    {
        lock (_sessionStateGate)
        {
            _sessionState = state;
        }
    }

    private bool ReconcileCredentialPresence()
    {
        var presence = _cache.CredentialStatus;
        lock (_sessionStateGate)
        {
            _sessionState = CredentialSessionPresentation.Reconcile(
                presence,
                _sessionState);
        }

        return presence == CredentialPresence.Present;
    }
}

public static class BrowserLauncher
{
    public static void Open(string url)
    {
        _ = Process.Start(new ProcessStartInfo(url)
        {
            UseShellExecute = true,
        }) ?? throw new InvalidOperationException("Windows could not open the default browser.");
    }
}
