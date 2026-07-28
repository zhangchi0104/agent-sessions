using System.Diagnostics;
using TokenStats.Core;

namespace TokenStats.App.Infrastructure;

public sealed class ClaudeAuthSession : IAgentAuthSession
{
    private readonly AgentTokenCache _cache;
    private readonly OAuthHttpClient _client;
    private readonly object _pendingGate = new();
    private (Pkce Pkce, string State)? _pending;

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
    }

    public bool IsSignedIn => _cache.IsSignedIn;
    public string? AccountId => null;

    public Task<string> ValidAccessTokenAsync(
        CancellationToken cancellationToken = default) =>
        _cache.ValidAccessTokenAsync(cancellationToken);

    public Task BeginSignInAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var pending = (Pkce: OAuthHelpers.MakePkce(), State: OAuthHelpers.MakeState());
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
        (Pkce Pkce, string State)? pending;
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
        await _cache.AdoptAsync(tokens, cancellationToken).ConfigureAwait(false);
        lock (_pendingGate)
        {
            _pending = null;
        }
    }

    public void SignOut()
    {
        _cache.SignOut();
        lock (_pendingGate)
        {
            _pending = null;
        }
    }
}

public sealed class CodexAuthSession : IAgentAuthSession
{
    private readonly AgentTokenCache _cache;
    private readonly OAuthHttpClient _client;

    public CodexAuthSession(
        ITokenStore store,
        OAuthHttpClient client,
        Func<DateTimeOffset>? now = null)
    {
        _client = client;
        _cache = new AgentTokenCache(
            store,
            (expired, cancellationToken) =>
                client.RefreshCodexAsync(expired, cancellationToken),
            now);
    }

    public bool IsSignedIn => _cache.IsSignedIn;
    public string? AccountId => _cache.AccountId;

    public Task<string> ValidAccessTokenAsync(
        CancellationToken cancellationToken = default) =>
        _cache.ValidAccessTokenAsync(cancellationToken);

    public async Task BeginSignInAsync(CancellationToken cancellationToken = default)
    {
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

        await _cache.AdoptAsync(tokens, cancellationToken).ConfigureAwait(false);
    }

    public Task CompleteSignInAsync(
        string pastedCode,
        CancellationToken cancellationToken = default) =>
        Task.FromException(
            new InvalidOperationException(
                "Codex completes sign-in automatically in the browser."));

    public void SignOut() => _cache.SignOut();
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
