using System.Net.Http.Headers;
using System.Runtime.ExceptionServices;
using System.Text;
using System.Text.Json;

namespace TokenStats.Core;

public interface ITokenStore
{
    OAuthTokens? Load();
    void Save(OAuthTokens tokens);
    void Clear();
}

public sealed class AgentTokenCache
{
    private const string PersistenceDiagnostic =
        "The refreshed session could not be saved to Windows Credential Manager.";
    private readonly ITokenStore _store;
    private readonly Func<OAuthTokens, CancellationToken, Task<OAuthTokens>> _refreshTokens;
    private readonly Func<DateTimeOffset> _now;
    private readonly object _commitGate = new();
    private volatile OAuthTokens? _cached;
    private volatile bool _loaded;
    private bool _credentialLoadUnavailable;
    private int _signOutGeneration;
    private int _tokenRevision;
    private RefreshFlight? _refreshFlight;
    private OAuthRefreshException? _terminalRefreshFailure;
    private PendingTokenPersistence? _pendingTokenPersistence;

    private sealed class RefreshFlight
    {
        public RefreshFlight(
            int credentialGeneration,
            int tokenRevision,
            OAuthTokens source)
        {
            CredentialGeneration = credentialGeneration;
            TokenRevision = tokenRevision;
            Source = source;
        }

        public int CredentialGeneration { get; private set; }
        public int TokenRevision { get; }
        public OAuthTokens Source { get; }
        public CancellationTokenSource Lifetime { get; } = new();
        public TaskCompletionSource<string> Completion { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public void RebaseCredentialGeneration(int credentialGeneration) =>
            CredentialGeneration = credentialGeneration;
    }

    private sealed record PendingTokenPersistence(
        OAuthTokens Tokens,
        OAuthTokens Replacing);

    public AgentTokenCache(
        ITokenStore store,
        Func<OAuthTokens, CancellationToken, Task<OAuthTokens>> refreshTokens,
        Func<DateTimeOffset>? now = null)
    {
        _store = store;
        _refreshTokens = refreshTokens;
        _now = now ?? (() => DateTimeOffset.Now);
    }

    public OAuthTokens? Tokens
    {
        get
        {
            lock (_commitGate)
            {
                return LoadTokensLocked();
            }
        }
    }

    public CredentialPresence CredentialStatus
    {
        get
        {
            lock (_commitGate)
            {
                _ = LoadTokensLocked();
                if (_credentialLoadUnavailable)
                {
                    return CredentialPresence.TemporarilyUnavailable;
                }

                return _cached is null
                    ? CredentialPresence.Absent
                    : CredentialPresence.Present;
            }
        }
    }

    public bool IsSignedIn => CredentialStatus == CredentialPresence.Present;

    public string? AccountId => Tokens?.AccountId;

    /// <summary>
    /// A safe, token-free diagnostic while an accepted rotation exists only in
    /// memory. Session presentation retains this warning across successful Usage
    /// calls until compare-and-replace persistence succeeds or durable state wins.
    /// </summary>
    public string? PendingPersistenceDiagnostic
    {
        get
        {
            lock (_commitGate)
            {
                return _pendingTokenPersistence is null
                    ? null
                    : PersistenceDiagnostic;
            }
        }
    }

    /// <summary>
    /// Captures the current credential ownership generation before an OAuth
    /// round trip. Passing it back to AdoptAsync prevents a sign-out that
    /// happened while the browser was open from being overwritten by a late
    /// token response.
    /// </summary>
    public int CaptureCredentialGeneration() =>
        Volatile.Read(ref _signOutGeneration);

    public Task AdoptAsync(
        OAuthTokens tokens,
        CancellationToken cancellationToken = default) =>
        AdoptAsync(
            tokens,
            CaptureCredentialGeneration(),
            cancellationToken);

    public Task AdoptAsync(
        OAuthTokens tokens,
        int expectedCredentialGeneration,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RefreshFlight? abandonedFlight;
        lock (_commitGate)
        {
            if (expectedCredentialGeneration !=
                Volatile.Read(ref _signOutGeneration))
            {
                throw UsageException.NotSignedIn();
            }

            // Persist first so a failed save cannot create a phantom login.
            // Once it succeeds, the replacement owns a new generation and any
            // old refresh flight becomes stale immediately.
            _store.Save(tokens);
            abandonedFlight = _refreshFlight;
            _refreshFlight = null;
            _cached = tokens;
            _loaded = true;
            _credentialLoadUnavailable = false;
            _tokenRevision++;
            _signOutGeneration++;
            _terminalRefreshFailure = null;
            _pendingTokenPersistence = null;
        }

        InvalidateFlight(abandonedFlight);
        return Task.CompletedTask;
    }

    public void SignOut()
    {
        RefreshFlight? abandonedFlight = null;
        ExceptionDispatchInfo? clearFailure = null;
        lock (_commitGate)
        {
            try
            {
                _store.Clear();
            }
            catch (Exception exception)
            {
                clearFailure = ExceptionDispatchInfo.Capture(exception);
            }

            if (clearFailure is null)
            {
                // Durable deletion committed, so no late OAuth response may
                // restore the account that the user explicitly removed.
                abandonedFlight = _refreshFlight;
                _refreshFlight = null;
                _signOutGeneration++;
                _cached = null;
                _loaded = true;
                _credentialLoadUnavailable = false;
                _tokenRevision++;
                _terminalRefreshFailure = null;
                _pendingTokenPersistence = null;
            }
            else
            {
                // The account remains connected when Credential Manager rejects
                // deletion. Invalidate browser login responses captured before
                // the attempt, but preserve an accepted in-flight refresh and
                // let it publish the only usable rotated credential.
                _signOutGeneration++;
                _refreshFlight?.RebaseCredentialGeneration(_signOutGeneration);
            }
        }

        try
        {
            InvalidateFlight(abandonedFlight);
        }
        finally
        {
            // Preserve the Credential Manager exception even if cancellation
            // callbacks on the abandoned flight also fail.
            clearFailure?.Throw();
        }
    }

    public async Task<string> ValidAccessTokenAsync(
        CancellationToken cancellationToken = default) =>
        await AccessTokenAsync(forceRefresh: false, cancellationToken)
            .ConfigureAwait(false);

    /// <summary>
    /// Refreshes even an unexpired token. Concurrent callers that observed the
    /// same token revision share the first rotation instead of reusing the old
    /// refresh token or immediately rotating the replacement again.
    /// </summary>
    public async Task<string> ForceRefreshAccessTokenAsync(
        CancellationToken cancellationToken = default) =>
        await AccessTokenAsync(forceRefresh: true, cancellationToken)
            .ConfigureAwait(false);

    private async Task<string> AccessTokenAsync(
        bool forceRefresh,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RefreshFlight flight;
        var ownsFlight = false;
        var canFallbackAfterTransient = false;
        int requestedGeneration;
        lock (_commitGate)
        {
            var current = LoadTokensLocked() ?? throw UsageException.NotSignedIn();
            requestedGeneration = _signOutGeneration;
            var persistenceFailure = ResolvePendingTokenPersistenceLocked();
            current = LoadTokensLocked() ?? throw UsageException.NotSignedIn();
            if (persistenceFailure is not null)
            {
                // A still-fresh bearer remains usable in this process while the
                // durable compare-and-replace is retried later. Never consume a
                // second refresh grant until the accepted rotation is durable.
                if (!forceRefresh && !current.IsExpired(_now()))
                {
                    return current.AccessToken;
                }

                throw persistenceFailure;
            }

            if (_terminalRefreshFailure is { } terminalFailure)
            {
                throw terminalFailure;
            }

            // Join an already registered rotation before considering the
            // unexpired access-token fast path. A normal usage caller then
            // observes terminal quarantine, while transient validation failure
            // can still fall back to the valid bearer below.
            if (_refreshFlight is { } existing)
            {
                if (existing.CredentialGeneration != requestedGeneration ||
                    existing.TokenRevision != _tokenRevision)
                {
                    throw UsageException.NotSignedIn();
                }

                flight = existing;
                canFallbackAfterTransient =
                    !forceRefresh && !current.IsExpired(_now());
            }
            else if (!forceRefresh && !current.IsExpired(_now()))
            {
                return current.AccessToken;
            }
            else
            {
                flight = new RefreshFlight(
                    requestedGeneration,
                    _tokenRevision,
                    current);
                _refreshFlight = flight;
                ownsFlight = true;
            }
        }

        if (ownsFlight)
        {
            _ = RunRefreshFlightAsync(flight);
        }

        try
        {
            return await flight.Completion.Task.WaitAsync(cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (
            canFallbackAfterTransient &&
            exception is not TokenPersistenceException &&
            exception is not OAuthRefreshException { IsTerminal: true })
        {
            // A proactive check that is only temporarily unverifiable must not
            // block ordinary usage while the old access token remains valid.
            // Credential replacement and terminal rejection never take this
            // fallback path.
            lock (_commitGate)
            {
                if (requestedGeneration != _signOutGeneration)
                {
                    throw UsageException.NotSignedIn();
                }

                if (_terminalRefreshFailure is { } terminalFailure)
                {
                    throw terminalFailure;
                }

                var current = LoadTokensLocked() ??
                    throw UsageException.NotSignedIn();
                if (!current.IsExpired(_now()))
                {
                    return current.AccessToken;
                }
            }

            throw;
        }
    }

    private async Task RunRefreshFlightAsync(RefreshFlight flight)
    {
        OAuthTokens refreshed;
        try
        {
            refreshed = await _refreshTokens(flight.Source, flight.Lifetime.Token)
                .ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            Exception refreshFailure;
            lock (_commitGate)
            {
                if (!IsCurrentFlightLocked(flight))
                {
                    refreshFailure = UsageException.NotSignedIn();
                }
                else
                {
                    _refreshFlight = null;
                    if (exception is OAuthRefreshException
                        {
                            IsTerminal: true,
                        } terminal)
                    {
                        _terminalRefreshFailure = terminal;
                    }

                    refreshFailure = exception;
                }
            }

            flight.Completion.TrySetException(refreshFailure);
            return;
        }

        string? accessToken = null;
        Exception? completionFailure = null;
        lock (_commitGate)
        {
            if (!IsCurrentFlightLocked(flight))
            {
                completionFailure = UsageException.NotSignedIn();
            }
            else
            {
                // A refresh token may be single-use. Publish the rotated token
                // before durable persistence so this process never retries the
                // now-invalid predecessor after a credential-store failure.
                _cached = refreshed;
                _loaded = true;
                _credentialLoadUnavailable = false;
                _tokenRevision++;
                _refreshFlight = null;
                _terminalRefreshFailure = null;
                TokenPersistenceException? persistenceFailure = null;
                if (refreshed != flight.Source)
                {
                    try
                    {
                        _store.Save(refreshed);
                        _pendingTokenPersistence = null;
                    }
                    catch (Exception exception)
                    {
                        // Keep the exact predecessor so a later retry cannot
                        // overwrite a newer login, rotation, or sign-out.
                        _pendingTokenPersistence = new PendingTokenPersistence(
                            refreshed,
                            flight.Source);
                        persistenceFailure = CredentialPersistenceFailure(exception);
                    }
                }
                else
                {
                    _pendingTokenPersistence = null;
                }

                if (refreshed.IsExpired(_now()))
                {
                    completionFailure = new RefreshedAccessTokenUnavailableException(
                        persistenceFailure is not null);
                }
                else if (persistenceFailure is not null)
                {
                    completionFailure = persistenceFailure;
                }
                else
                {
                    accessToken = refreshed.AccessToken;
                }
            }
        }

        if (completionFailure is { } failure)
        {
            flight.Completion.TrySetException(failure);
        }
        else
        {
            flight.Completion.TrySetResult(accessToken!);
        }
    }

    private bool IsCurrentFlightLocked(RefreshFlight flight) =>
        ReferenceEquals(_refreshFlight, flight) &&
        flight.CredentialGeneration == _signOutGeneration &&
        flight.TokenRevision == _tokenRevision;

    private static void InvalidateFlight(RefreshFlight? flight)
    {
        if (flight is null)
        {
            return;
        }

        flight.Completion.TrySetException(UsageException.NotSignedIn());
        try
        {
            flight.Lifetime.Cancel();
        }
        catch (AggregateException)
        {
            // Callback failures belong to the abandoned refresh. Credential
            // replacement or deletion has already committed, so cleanup must
            // not make the completed operation appear to have failed.
        }
    }

    /// <summary>
    /// Retries a previously accepted token rotation without consuming another
    /// refresh grant. The durable predecessor acts as the compare value: a
    /// different value belongs to a newer credential operation and is adopted
    /// instead of being overwritten.
    /// </summary>
    private TokenPersistenceException? ResolvePendingTokenPersistenceLocked()
    {
        if (_pendingTokenPersistence is not { } pending)
        {
            return null;
        }

        OAuthTokens? persisted;
        try
        {
            persisted = _store.Load();
        }
        catch (Exception exception)
        {
            return CredentialPersistenceFailure(exception);
        }

        if (persisted == pending.Tokens)
        {
            _pendingTokenPersistence = null;
            return null;
        }

        if (persisted == pending.Replacing)
        {
            try
            {
                _store.Save(pending.Tokens);
                _pendingTokenPersistence = null;
                return null;
            }
            catch (Exception exception)
            {
                return CredentialPersistenceFailure(exception);
            }
        }

        // Another credential operation already changed or deleted durable
        // state. Converge on that result and discard the stale persistence debt.
        _pendingTokenPersistence = null;
        _cached = persisted;
        _loaded = true;
        _credentialLoadUnavailable = false;
        _tokenRevision++;
        _terminalRefreshFailure = null;
        return null;
    }

    private static TokenPersistenceException CredentialPersistenceFailure(
        Exception exception) =>
        new(
            PersistenceDiagnostic,
            exception);

    private OAuthTokens? LoadTokensLocked()
    {
        if (_loaded)
        {
            return _cached;
        }

        try
        {
            _cached = _store.Load();
            _loaded = true;
            _credentialLoadUnavailable = false;
        }
        catch
        {
            // A locked/unavailable credential store is not the same as no
            // account. Leave it unloaded so a later read can retry.
            _cached = null;
            _credentialLoadUnavailable = true;
        }

        return _cached;
    }
}

public interface IAgentAuthSession
{
    bool IsSignedIn { get; }
    string? AccountId { get; }
    AuthSessionState SessionState { get; }
    Task<string> ValidAccessTokenAsync(CancellationToken cancellationToken = default);
    Task BeginSignInAsync(CancellationToken cancellationToken = default);
    Task CompleteSignInAsync(
        string pastedCode,
        CancellationToken cancellationToken = default);
    void MarkUsageSucceeded(DateTimeOffset validatedAt);
    void MarkUsageFailed(string diagnostic);
    void SignOut();
}

/// <summary>
/// Optional capability for sessions that can rotate credentials after a usage
/// request rejects the current access token. This is separate from proactive
/// validation: Claude and Cursor use it only to recover from HTTP 401, while
/// Codex also validates at startup and on manual refresh.
/// </summary>
public interface IUnauthorizedRecoveryAuthSession
{
    Task<AuthSessionState> ForceValidateSessionAsync(
        CancellationToken cancellationToken = default);

    void RequireReauthentication(
        OAuthRefreshFailureReason reason,
        string diagnostic);
}

/// <summary>
/// Marker capability for sessions whose refresh grant is authoritative enough
/// to validate proactively. Only Codex is rotated merely because TokenStats
/// started or the user requested a manual refresh.
/// </summary>
public interface IProactiveAuthSession : IUnauthorizedRecoveryAuthSession
{
}

public interface IUsageProvider
{
    Task<IReadOnlyList<UsageWindow>> FetchUsageAsync(
        CancellationToken cancellationToken = default);
}

public sealed class OAuthHttpClient
{
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(20);
    private readonly HttpClient _httpClient;
    private readonly TimeProvider _timeProvider;
    private readonly TimeSpan _cursorLoginTimeout;
    private readonly TimeSpan _cursorPollInterval;

    public OAuthHttpClient(
        HttpClient httpClient,
        TimeProvider? timeProvider = null,
        TimeSpan? cursorLoginTimeout = null,
        TimeSpan? cursorPollInterval = null)
    {
        _httpClient = httpClient;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _cursorLoginTimeout = cursorLoginTimeout ?? TimeSpan.FromMinutes(5);
        _cursorPollInterval = cursorPollInterval ?? TimeSpan.FromSeconds(1);
        if (_cursorLoginTimeout < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(cursorLoginTimeout));
        }

        if (_cursorPollInterval < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(cursorPollInterval));
        }
    }

    public async Task<OAuthTokens> ExchangeClaudeCodeAsync(
        string code,
        string verifier,
        string state,
        CancellationToken cancellationToken = default)
    {
        var body = new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
            ["redirect_uri"] = ClaudeOAuthFlow.RedirectUri,
            ["client_id"] = ClaudeOAuthFlow.ClientId,
            ["code_verifier"] = verifier,
            ["state"] = state,
        };
        var json = await PostJsonAsync(
            ClaudeOAuthFlow.TokenEndpoint,
            body,
            cancellationToken).ConfigureAwait(false);
        return ClaudeOAuthFlow.ParseTokens(json);
    }

    public async Task<OAuthTokens> RefreshClaudeCodeAsync(
        string refreshToken,
        CancellationToken cancellationToken = default)
    {
        var body = new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken,
            ["client_id"] = ClaudeOAuthFlow.ClientId,
        };
        var json = await PostRefreshJsonAsync(
            ClaudeOAuthFlow.TokenEndpoint,
            body,
            cancellationToken).ConfigureAwait(false);
        return ClaudeOAuthFlow.ParseTokens(json);
    }

    public async Task<OAuthTokens> ExchangeCodexAsync(
        string code,
        string verifier,
        string redirectUri,
        CancellationToken cancellationToken = default)
    {
        var body = new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
            ["redirect_uri"] = redirectUri,
            ["client_id"] = CodexOAuthFlow.ClientId,
            ["code_verifier"] = verifier,
        };
        var json = await PostCodexCodeExchangeFormAsync(
            CodexOAuthFlow.TokenEndpoint,
            body,
            cancellationToken).ConfigureAwait(false);
        return CodexOAuthFlow.ParseTokens(json);
    }

    public async Task<OAuthTokens> RefreshCodexAsync(
        OAuthTokens previous,
        CancellationToken cancellationToken = default)
    {
        var body = new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = previous.RefreshToken,
            ["client_id"] = CodexOAuthFlow.ClientId,
        };
        var json = await PostRefreshJsonAsync(
            CodexOAuthFlow.TokenEndpoint,
            body,
            cancellationToken).ConfigureAwait(false);
        return CodexOAuthFlow.ParseRefreshTokens(json, previous);
    }

    public async Task<OAuthTokens> WaitForCursorLoginAsync(
        Pkce pkce,
        string uuid,
        CancellationToken cancellationToken = default)
    {
        var pollUrl = CursorOAuthFlow.PollUrl(pkce, uuid);
        var startedAt = _timeProvider.GetTimestamp();
        while (true)
        {
            var remaining = RemainingCursorLoginTime(startedAt);
            if (remaining <= TimeSpan.Zero)
            {
                break;
            }

            cancellationToken.ThrowIfCancellationRequested();
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken);
            timeout.CancelAfter(remaining < RequestTimeout ? remaining : RequestTimeout);
            try
            {
                using var response = await _httpClient.GetAsync(pollUrl, timeout.Token)
                    .ConfigureAwait(false);
                var body = await response.Content.ReadAsStringAsync(timeout.Token)
                    .ConfigureAwait(false);
                if (response.IsSuccessStatusCode)
                {
                    return CursorOAuthFlow.ParsePollTokens(body);
                }

                if (response.StatusCode != System.Net.HttpStatusCode.NotFound)
                {
                    throw UsageException.BadResponse(
                        (int)response.StatusCode,
                        OAuthFailureSummary(body, "OAuth login rejected"));
                }
            }
            catch (OperationCanceledException)
                when (!cancellationToken.IsCancellationRequested)
            {
                if (RemainingCursorLoginTime(startedAt) <= TimeSpan.Zero)
                {
                    break;
                }

                continue;
            }

            remaining = RemainingCursorLoginTime(startedAt);
            if (remaining <= TimeSpan.Zero)
            {
                break;
            }

            var delay = remaining < _cursorPollInterval
                ? remaining
                : _cursorPollInterval;
            await Task.Delay(delay, _timeProvider, cancellationToken).ConfigureAwait(false);
        }

        throw new TimeoutException("Cursor sign-in timed out.");
    }

    private TimeSpan RemainingCursorLoginTime(long startedAt)
    {
        var remaining = _cursorLoginTimeout - _timeProvider.GetElapsedTime(startedAt);
        return remaining > TimeSpan.Zero ? remaining : TimeSpan.Zero;
    }

    public async Task<OAuthTokens> RefreshCursorAsync(
        OAuthTokens previous,
        CancellationToken cancellationToken = default)
    {
        var body = new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["client_id"] = CursorOAuthFlow.ClientId,
            ["refresh_token"] = previous.RefreshToken,
        };
        var json = await PostRefreshJsonAsync(
            CursorOAuthFlow.TokenEndpoint,
            body,
            cancellationToken).ConfigureAwait(false);
        return CursorOAuthFlow.ParseRefreshTokens(json, previous);
    }

    private async Task<string> PostJsonAsync(
        string endpoint,
        IReadOnlyDictionary<string, string> body,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new StringContent(
                JsonSerializer.Serialize(body),
                Encoding.UTF8,
                "application/json"),
        };
        return await SendAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<string> PostCodexCodeExchangeFormAsync(
        string endpoint,
        IReadOnlyDictionary<string, string> body,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new FormUrlEncodedContent(body),
        };
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeout.CancelAfter(RequestTimeout);
        using var response = await _httpClient.SendAsync(request, timeout.Token)
            .ConfigureAwait(false);
        var responseBody = await response.Content.ReadAsStringAsync(timeout.Token)
            .ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw UsageException.BadResponse(
                (int)response.StatusCode,
                OAuthFailureSummary(
                    responseBody,
                    "OAuth token exchange rejected"));
        }

        return responseBody;
    }

    private async Task<string> PostRefreshJsonAsync(
        string endpoint,
        IReadOnlyDictionary<string, string> body,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new StringContent(
                JsonSerializer.Serialize(body),
                Encoding.UTF8,
                "application/json"),
        };
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeout.CancelAfter(RequestTimeout);
        using var response = await _httpClient.SendAsync(request, timeout.Token)
            .ConfigureAwait(false);
        var responseBody = await response.Content.ReadAsStringAsync(timeout.Token)
            .ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw ClassifyRefreshFailure(
                (int)response.StatusCode,
                responseBody);
        }

        return responseBody;
    }

    private static OAuthRefreshException ClassifyRefreshFailure(
        int statusCode,
        string responseBody)
    {
        var candidates = ExtractOAuthErrorCodes(responseBody);
        var known = candidates
            .Select(code => (Code: code, Reason: KnownTerminalReason(code)))
            .FirstOrDefault(item => item.Reason is not null);
        if (known.Reason is { } knownReason)
        {
            return new OAuthRefreshException(
                statusCode,
                known.Code,
                knownReason,
                isTerminal: true);
        }

        var errorCode = candidates.FirstOrDefault();
        if (statusCode == 401)
        {
            return new OAuthRefreshException(
                statusCode,
                errorCode,
                OAuthRefreshFailureReason.Unauthorized,
                isTerminal: true);
        }

        return new OAuthRefreshException(
            statusCode,
            errorCode,
            OAuthRefreshFailureReason.Other,
            isTerminal: false);
    }

    private static OAuthRefreshFailureReason? KnownTerminalReason(string code) =>
        code.ToLowerInvariant() switch
        {
            "refresh_token_expired" => OAuthRefreshFailureReason.Expired,
            "refresh_token_reused" => OAuthRefreshFailureReason.Reused,
            "refresh_token_invalidated" => OAuthRefreshFailureReason.Revoked,
            "invalid_grant" => OAuthRefreshFailureReason.InvalidGrant,
            _ => null,
        };

    private static IReadOnlyList<string> ExtractOAuthErrorCodes(string responseBody)
    {
        try
        {
            using var document = JsonDocument.Parse(responseBody);
            var candidates = new List<string>();
            CollectOAuthErrorCodes(document.RootElement, candidates, depth: 0);
            return candidates.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static void CollectOAuthErrorCodes(
        JsonElement element,
        ICollection<string> candidates,
        int depth)
    {
        if (depth > 6)
        {
            return;
        }

        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                var isCodeProperty =
                    property.NameEquals("code") ||
                    property.NameEquals("error_code") ||
                    property.NameEquals("type") ||
                    property.NameEquals("error");
                if (property.Value.ValueKind == JsonValueKind.String &&
                    SanitizeOAuthErrorCode(property.Value.GetString()) is { } code &&
                    (isCodeProperty ||
                     (property.NameEquals("message") &&
                      KnownTerminalReason(code) is not null)))
                {
                    candidates.Add(code);
                }

                if (property.Value.ValueKind is JsonValueKind.Object or
                    JsonValueKind.Array)
                {
                    CollectOAuthErrorCodes(property.Value, candidates, depth + 1);
                }
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                CollectOAuthErrorCodes(item, candidates, depth + 1);
            }
        }
    }

    private static string? SanitizeOAuthErrorCode(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        return trimmed.Length <= 80 && trimmed.All(character =>
            char.IsAsciiLetterOrDigit(character) ||
            character is '_' or '-' or '.')
            ? trimmed
            : null;
    }

    private static string OAuthFailureSummary(
        string responseBody,
        string operation)
    {
        var code = ExtractOAuthErrorCodes(responseBody).FirstOrDefault();
        return code is null ? operation : $"{operation} ({code})";
    }

    private async Task<string> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(RequestTimeout);
        using var response = await _httpClient.SendAsync(request, timeout.Token)
            .ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(timeout.Token)
            .ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw UsageException.BadResponse(
                (int)response.StatusCode,
                OAuthFailureSummary(body, "OAuth request rejected"));
        }

        return body;
    }
}

public sealed class ClaudeUsageProvider : IUsageProvider
{
    public const string UsageEndpoint = "https://api.anthropic.com/api/oauth/usage";
    private readonly HttpClient _httpClient;
    private readonly Func<CancellationToken, Task<string>> _accessToken;

    public ClaudeUsageProvider(
        HttpClient httpClient,
        Func<CancellationToken, Task<string>> accessToken)
    {
        _httpClient = httpClient;
        _accessToken = accessToken;
    }

    public async Task<IReadOnlyList<UsageWindow>> FetchUsageAsync(
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, UsageEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            await _accessToken(cancellationToken).ConfigureAwait(false));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        var body = await SendAsync(request, cancellationToken).ConfigureAwait(false);
        var windows = ClaudeUsageParser.Parse(body);
        if (windows.Count == 0)
        {
            throw UsageException.NoWindows(body);
        }

        return windows;
    }

    private async Task<string> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        using var response = await _httpClient.SendAsync(request, timeout.Token)
            .ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(timeout.Token)
            .ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw UsageException.BadResponse((int)response.StatusCode, body);
        }

        return body;
    }
}

public sealed class CodexUsageProvider : IUsageProvider
{
    public const string UsageEndpoint = "https://chatgpt.com/backend-api/wham/usage";
    private readonly HttpClient _httpClient;
    private readonly Func<CancellationToken, Task<string>> _accessToken;
    private readonly Func<string?> _accountId;

    public CodexUsageProvider(
        HttpClient httpClient,
        Func<CancellationToken, Task<string>> accessToken,
        Func<string?> accountId)
    {
        _httpClient = httpClient;
        _accessToken = accessToken;
        _accountId = accountId;
    }

    public async Task<IReadOnlyList<UsageWindow>> FetchUsageAsync(
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, UsageEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            await _accessToken(cancellationToken).ConfigureAwait(false));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.UserAgent.ParseAdd("TokenStats-Windows/0.1");
        if (_accountId() is { Length: > 0 } accountId)
        {
            request.Headers.TryAddWithoutValidation("ChatGPT-Account-Id", accountId);
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        using var response = await _httpClient.SendAsync(request, timeout.Token)
            .ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(timeout.Token)
            .ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw UsageException.BadResponse(
                (int)response.StatusCode,
                FailureSummary(body));
        }

        var windows = CodexUsageParser.Parse(body);
        if (windows.Count == 0 &&
            !CodexUsageParser.IsRecognizedNoLimit(body))
        {
            throw UsageException.NoWindows(FailureSummary(body));
        }

        return windows;
    }

    private static string FailureSummary(string body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            if (FindSafeDiagnostic(
                    document.RootElement,
                    depth: 0,
                    out var field,
                    out var value))
            {
                return $"Codex usage request failed ({field}: {value}).";
            }
        }
        catch (JsonException)
        {
        }

        return "Codex usage request failed.";
    }

    private static bool FindSafeDiagnostic(
        JsonElement element,
        int depth,
        out string field,
        out string value)
    {
        field = string.Empty;
        value = string.Empty;
        if (depth > 6)
        {
            return false;
        }

        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                var allowedField =
                    property.Name.Equals("code", StringComparison.OrdinalIgnoreCase) ||
                    property.Name.Equals("type", StringComparison.OrdinalIgnoreCase);
                if (allowedField &&
                    property.Value.ValueKind == JsonValueKind.String &&
                    SafeDiagnosticValue(property.Value.GetString()) is { } safe)
                {
                    field = property.Name.Equals(
                        "code",
                        StringComparison.OrdinalIgnoreCase)
                        ? "code"
                        : "type";
                    value = safe;
                    return true;
                }

                if ((property.Value.ValueKind is JsonValueKind.Object or
                     JsonValueKind.Array) &&
                    FindSafeDiagnostic(
                        property.Value,
                        depth + 1,
                        out field,
                        out value))
                {
                    return true;
                }
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                if (FindSafeDiagnostic(
                        item,
                        depth + 1,
                        out field,
                        out value))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static string? SafeDiagnosticValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        return trimmed.Length <= 80 && trimmed.All(character =>
            char.IsAsciiLetterOrDigit(character) ||
            character is '_' or '-' or '.')
            ? trimmed
            : null;
    }
}

public sealed class CursorUsageProvider : IUsageProvider
{
    public const string UsageEndpoint =
        "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage";
    private readonly HttpClient _httpClient;
    private readonly Func<CancellationToken, Task<string>> _accessToken;

    public CursorUsageProvider(
        HttpClient httpClient,
        Func<CancellationToken, Task<string>> accessToken)
    {
        _httpClient = httpClient;
        _accessToken = accessToken;
    }

    public async Task<IReadOnlyList<UsageWindow>> FetchUsageAsync(
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, UsageEndpoint)
        {
            Content = new StringContent("{}", Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            await _accessToken(cancellationToken).ConfigureAwait(false));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.TryAddWithoutValidation("Connect-Protocol-Version", "1");
        request.Headers.TryAddWithoutValidation("x-request-id", Guid.NewGuid().ToString());

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        using var response = await _httpClient.SendAsync(request, timeout.Token)
            .ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(timeout.Token)
            .ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw UsageException.BadResponse((int)response.StatusCode, body);
        }

        var windows = CursorUsageParser.Parse(body);
        if (windows.Count == 0)
        {
            throw UsageException.NoWindows(body);
        }

        return windows;
    }
}
