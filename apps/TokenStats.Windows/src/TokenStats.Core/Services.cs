using System.Net.Http.Headers;
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
    private readonly ITokenStore _store;
    private readonly Func<OAuthTokens, CancellationToken, Task<OAuthTokens>> _refreshTokens;
    private readonly Func<DateTimeOffset> _now;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly object _commitGate = new();
    private volatile OAuthTokens? _cached;
    private volatile bool _loaded;
    private int _signOutGeneration;

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
                if (_loaded)
                {
                    return _cached;
                }

                try
                {
                    _cached = _store.Load();
                    _loaded = true;
                }
                catch
                {
                    // A locked/unavailable credential store is not the same as
                    // no account. Leave it unloaded so a later read can retry.
                    _cached = null;
                }

                return _cached;
            }
        }
    }

    public bool IsSignedIn => Tokens is not null;

    public string? AccountId => Tokens?.AccountId;

    public async Task AdoptAsync(
        OAuthTokens tokens,
        CancellationToken cancellationToken = default)
    {
        var generation = Volatile.Read(ref _signOutGeneration);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            lock (_commitGate)
            {
                if (generation != Volatile.Read(ref _signOutGeneration))
                {
                    throw UsageException.NotSignedIn();
                }

                // Publish the new in-memory value only after persistence
                // succeeds, so a failed save cannot create a phantom login.
                _store.Save(tokens);
                _cached = tokens;
                _loaded = true;
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    public void SignOut()
    {
        lock (_commitGate)
        {
            Interlocked.Increment(ref _signOutGeneration);
            _store.Clear();
            _cached = null;
            _loaded = true;
        }
    }

    public async Task<string> ValidAccessTokenAsync(
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var generation = Volatile.Read(ref _signOutGeneration);
            var current = Tokens ?? throw UsageException.NotSignedIn();
            if (!current.IsExpired(_now()))
            {
                lock (_commitGate)
                {
                    if (generation != Volatile.Read(ref _signOutGeneration))
                    {
                        throw UsageException.NotSignedIn();
                    }

                    return current.AccessToken;
                }
            }

            var refreshed = await _refreshTokens(current, cancellationToken)
                .ConfigureAwait(false);
            lock (_commitGate)
            {
                if (generation != Volatile.Read(ref _signOutGeneration))
                {
                    throw UsageException.NotSignedIn();
                }

                _store.Save(refreshed);
                _cached = refreshed;
                _loaded = true;
                return refreshed.AccessToken;
            }
        }
        finally
        {
            _gate.Release();
        }
    }
}

public interface IAgentAuthSession
{
    bool IsSignedIn { get; }
    string? AccountId { get; }
    Task<string> ValidAccessTokenAsync(CancellationToken cancellationToken = default);
    Task BeginSignInAsync(CancellationToken cancellationToken = default);
    Task CompleteSignInAsync(
        string pastedCode,
        CancellationToken cancellationToken = default);
    void SignOut();
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
        var json = await PostJsonAsync(
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
        var json = await PostFormAsync(
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
            ["scope"] = CodexOAuthFlow.Scopes,
        };
        var json = await PostFormAsync(
            CodexOAuthFlow.TokenEndpoint,
            body,
            cancellationToken).ConfigureAwait(false);
        var refreshed = CodexOAuthFlow.ParseTokens(json);
        return refreshed with
        {
            RefreshToken = string.IsNullOrEmpty(refreshed.RefreshToken)
                ? previous.RefreshToken
                : refreshed.RefreshToken,
            AccountId = refreshed.AccountId ?? previous.AccountId,
        };
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
                    throw UsageException.BadResponse((int)response.StatusCode, body);
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
        var json = await PostJsonAsync(
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

    private async Task<string> PostFormAsync(
        string endpoint,
        IReadOnlyDictionary<string, string> body,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new FormUrlEncodedContent(body),
        };
        return await SendAsync(request, cancellationToken).ConfigureAwait(false);
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
            throw UsageException.BadResponse((int)response.StatusCode, body);
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
            throw UsageException.BadResponse((int)response.StatusCode, body);
        }

        var windows = CodexUsageParser.Parse(body);
        if (windows.Count == 0 &&
            !CodexUsageParser.IsRecognizedNoLimit(body))
        {
            throw UsageException.NoWindows(body);
        }

        return windows;
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
