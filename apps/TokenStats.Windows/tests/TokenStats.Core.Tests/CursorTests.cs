using System.Globalization;
using System.Net;
using System.Text;
using TokenStats.Core;

namespace TokenStats.Core.Tests;

internal static class CursorTests
{
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;

    internal static void UsageParserReadsOfficialModelBucketsAtomically()
    {
        var windows = CursorUsageParser.Parse(
            """
            {
              "billingCycleEnd": 2000000000000,
              "planUsage": {
                "totalSpend": 900,
                "includedSpend": 365,
                "limit": 2000,
                "autoPercentUsed": 1.2166666666666666,
                "apiPercentUsed": 0,
                "totalPercentUsed": 1.0579710144927537
              },
              "enabled": true
            }
            """);
        Check.Equal(2, windows.Count);
        Check.Equal("Cursor Models", windows[0].Label);
        Check.Equal(1.2166666666666666d, windows[0].PercentConsumed);
        Check.Equal("Other Models", windows[1].Label);
        Check.Equal(0d, windows[1].PercentConsumed);
        Check.Equal(
            DateTimeOffset.FromUnixTimeMilliseconds(2_000_000_000_000),
            windows[0].ResetAt);
        Check.Equal(windows[0].ResetAt, windows[1].ResetAt);

        var stringTimestamp = CursorUsageParser.Parse(
            """{"billingCycleEnd":"1787443288000","planUsage":{"autoPercentUsed":1,"apiPercentUsed":0}}""");
        Check.Equal(1d, stringTimestamp[0].PercentConsumed);
        Check.Equal(
            DateTimeOffset.FromUnixTimeMilliseconds(1_787_443_288_000),
            stringTimestamp[0].ResetAt);

        var snakeCase = CursorUsageParser.Parse(
            """{"plan_usage":{"auto_percent_used":12.5,"api_percent_used":4}}""");
        Check.Equal(12.5d, snakeCase[0].PercentConsumed);
        Check.Equal(4d, snakeCase[1].PercentConsumed);
        Check.Equal(0, CursorUsageParser.Parse(
            """{"planUsage":{"includedSpend":365,"limit":2000,"totalPercentUsed":1.05}}""").Count);
        Check.Equal(0, CursorUsageParser.Parse(
            """{"planUsage":{"autoPercentUsed":12.5}}""").Count);
        Check.Equal(0, CursorUsageParser.Parse(
            """{"planUsage":{"apiPercentUsed":4}}""").Count);
        Check.Equal(0, CursorUsageParser.Parse(
            """{"enabled":false,"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2}}""").Count);
    }

    internal static void RegistryKeepsCursorOutOfTranscriptRoots()
    {
        Check.True(AgentRegistry.TranscriptRoots.Any(root => root.Id == AgentId.ClaudeCode));
        Check.True(AgentRegistry.TranscriptRoots.Any(root => root.Id == AgentId.Codex));
        Check.False(AgentRegistry.TranscriptRoots.Any(root => root.Id == AgentId.Cursor));
    }

    internal static void OAuthBuildsLoginAndRotatesTokens()
    {
        var pkce = new Pkce("verifier", "challenge");
        var authorize = CursorOAuthFlow.AuthorizeUrl(pkce, "uuid-123");
        Check.True(authorize.Contains("challenge=challenge", StringComparison.Ordinal));
        Check.True(authorize.Contains("uuid=uuid-123", StringComparison.Ordinal));
        Check.True(authorize.Contains("redirectTarget=cli", StringComparison.Ordinal));
        var poll = CursorOAuthFlow.PollUrl(pkce, "uuid-123");
        Check.True(poll.Contains("verifier=verifier", StringComparison.Ordinal));

        var payload = OAuthHelpers.Base64Url(
            Encoding.UTF8.GetBytes("""{"exp":2000000000}"""));
        var jwt = $"header.{payload}.signature";
        var tokens = CursorOAuthFlow.ParsePollTokens(
            $$"""{"accessToken":"{{jwt}}","refreshToken":"cursor-refresh"}""");
        Check.Equal(jwt, tokens.AccessToken);
        Check.Equal("cursor-refresh", tokens.RefreshToken);
        Check.Equal(DateTimeOffset.FromUnixTimeSeconds(2_000_000_000), tokens.ExpiresAt);

        var now = DateTimeOffset.Parse("2026-08-16T00:00:00Z", Invariant);
        var refreshed = CursorOAuthFlow.ParseRefreshTokens(
            """{"access_token":"rotated","expires_in":7200}""",
            tokens,
            now);
        Check.Equal("rotated", refreshed.AccessToken);
        Check.Equal("rotated", refreshed.RefreshToken);
        Check.Equal(now.AddHours(2), refreshed.ExpiresAt);
    }

    internal static async Task OAuthPollingUsesAnAbsoluteDeadline()
    {
        var handler = new RecordingHandler();
        handler.Enqueue(HttpStatusCode.NotFound, "{}");
        handler.Enqueue(
            HttpStatusCode.OK,
            """{"accessToken":"cursor-access","refreshToken":"cursor-refresh"}""");
        using var httpClient = new HttpClient(handler);
        var oauth = new OAuthHttpClient(
            httpClient,
            cursorLoginTimeout: TimeSpan.FromSeconds(1),
            cursorPollInterval: TimeSpan.Zero);

        var tokens = await oauth.WaitForCursorLoginAsync(
                new Pkce("cursor-verifier", "cursor-challenge"),
                "cursor-uuid")
            .ConfigureAwait(false);
        Check.Equal("cursor-access", tokens.AccessToken);
        Check.Equal(2, handler.Requests.Count);
        Check.True(handler.Requests[0].Uri.Query.Contains(
            "verifier=cursor-verifier",
            StringComparison.Ordinal));

        var expiredHandler = new RecordingHandler();
        using var expiredHttpClient = new HttpClient(expiredHandler);
        var expired = new OAuthHttpClient(
            expiredHttpClient,
            cursorLoginTimeout: TimeSpan.Zero,
            cursorPollInterval: TimeSpan.Zero);
        var timedOut = false;
        try
        {
            _ = await expired.WaitForCursorLoginAsync(
                    new Pkce("verifier", "challenge"),
                    "uuid")
                .ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            timedOut = true;
        }

        Check.True(timedOut, "An expired Cursor login deadline was accepted.");
        Check.Equal(0, expiredHandler.Requests.Count);
    }

    internal static async Task UsageProviderSendsHeadersAndRejectsPartialWindows()
    {
        var handler = new RecordingHandler();
        handler.Enqueue(
            HttpStatusCode.OK,
            """{"billingCycleEnd":2000000000000,"planUsage":{"autoPercentUsed":25,"apiPercentUsed":0}}""");
        handler.Enqueue(
            HttpStatusCode.OK,
            """{"billingCycleEnd":2000000000000,"planUsage":{"autoPercentUsed":25}}""");
        using var httpClient = new HttpClient(handler);
        var provider = new CursorUsageProvider(
            httpClient,
            _ => Task.FromResult("cursor-token"));

        Check.Equal(2, (await provider.FetchUsageAsync().ConfigureAwait(false)).Count);
        var request = handler.Requests[0];
        Check.Equal(HttpMethod.Post, request.Method);
        Check.Equal("Bearer cursor-token", request.Header("Authorization"));
        Check.Equal("1", request.Header("Connect-Protocol-Version"));
        Check.Equal("{}", request.Body);

        var rejectedPartial = false;
        try
        {
            _ = await provider.FetchUsageAsync().ConfigureAwait(false);
        }
        catch (UsageException)
        {
            rejectedPartial = true;
        }

        Check.True(rejectedPartial, "A partial Cursor usage payload was accepted.");
    }

    private sealed record RequestSnapshot(
        HttpMethod Method,
        Uri Uri,
        string Body,
        IReadOnlyDictionary<string, string> Headers)
    {
        internal string Header(string name) =>
            Headers.TryGetValue(name, out var value) ? value : string.Empty;
    }

    private sealed class RecordingHandler : HttpMessageHandler
    {
        private readonly Queue<(HttpStatusCode Status, string Body)> _responses = [];

        internal List<RequestSnapshot> Requests { get; } = [];

        internal void Enqueue(HttpStatusCode status, string body) =>
            _responses.Enqueue((status, body));

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            if (!_responses.TryDequeue(out var response))
            {
                throw new InvalidOperationException("No synthetic HTTP response was queued.");
            }

            var body = request.Content is null
                ? string.Empty
                : await request.Content.ReadAsStringAsync(cancellationToken)
                    .ConfigureAwait(false);
            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var header in request.Headers)
            {
                headers[header.Key] = string.Join(" ", header.Value);
            }

            if (request.Content is not null)
            {
                foreach (var header in request.Content.Headers)
                {
                    headers[header.Key] = string.Join(" ", header.Value);
                }
            }

            Requests.Add(new RequestSnapshot(
                request.Method,
                request.RequestUri ??
                throw new InvalidOperationException("Synthetic request had no URI."),
                body,
                headers));
            return new HttpResponseMessage(response.Status)
            {
                Content = new StringContent(response.Body, Encoding.UTF8, "application/json"),
            };
        }
    }
}
