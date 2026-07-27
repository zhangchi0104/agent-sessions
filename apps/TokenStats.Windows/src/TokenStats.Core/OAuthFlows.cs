using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace TokenStats.Core;

public static class OAuthHelpers
{
    public static Pkce MakePkce()
    {
        var verifier = Base64Url(RandomNumberGenerator.GetBytes(32));
        var challenge = Base64Url(SHA256.HashData(Encoding.UTF8.GetBytes(verifier)));
        return new Pkce(verifier, challenge);
    }

    public static string MakeState() =>
        Base64Url(RandomNumberGenerator.GetBytes(32));

    public static string Base64Url(ReadOnlySpan<byte> bytes) =>
        Convert.ToBase64String(bytes)
            .Replace("+", "-", StringComparison.Ordinal)
            .Replace("/", "_", StringComparison.Ordinal)
            .TrimEnd('=');

    public static byte[]? DecodeBase64Url(string value)
    {
        var normalized = value
            .Replace("-", "+", StringComparison.Ordinal)
            .Replace("_", "/", StringComparison.Ordinal);
        normalized = normalized.PadRight(
            normalized.Length + (4 - normalized.Length % 4) % 4,
            '=');
        try
        {
            return Convert.FromBase64String(normalized);
        }
        catch (FormatException)
        {
            return null;
        }
    }

    public static string BuildUrl(
        string endpoint,
        IEnumerable<KeyValuePair<string, string>> query)
    {
        var builder = new StringBuilder(endpoint);
        builder.Append('?');
        builder.AppendJoin(
            "&",
            query.Select(item =>
                $"{Uri.EscapeDataString(item.Key)}={Uri.EscapeDataString(item.Value)}"));
        return builder.ToString();
    }

    public static (string Code, string? State) SplitPastedCode(string pasted)
    {
        var parts = pasted.Trim().Split('#', 2);
        return (parts.ElementAtOrDefault(0) ?? string.Empty, parts.ElementAtOrDefault(1));
    }
}

public static class ClaudeOAuthFlow
{
    public const string ClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
    public const string AuthorizeEndpoint = "https://claude.com/cai/oauth/authorize";
    public const string TokenEndpoint = "https://platform.claude.com/v1/oauth/token";
    public const string RedirectUri = "https://platform.claude.com/oauth/code/callback";
    public const string Scopes = "org:create_api_key user:profile user:inference";

    public static string AuthorizeUrl(Pkce pkce, string state) =>
        OAuthHelpers.BuildUrl(
            AuthorizeEndpoint,
            new Dictionary<string, string>
            {
                ["code"] = "true",
                ["client_id"] = ClientId,
                ["response_type"] = "code",
                ["redirect_uri"] = RedirectUri,
                ["scope"] = Scopes,
                ["code_challenge"] = pkce.Challenge,
                ["code_challenge_method"] = "S256",
                ["state"] = state,
            });

    public static OAuthTokens ParseTokens(
        string json,
        DateTimeOffset? now = null)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        return new OAuthTokens(
            root.GetProperty("access_token").GetString() ??
                throw new JsonException("Missing access_token."),
            root.GetProperty("refresh_token").GetString() ??
                throw new JsonException("Missing refresh_token."),
            (now ?? DateTimeOffset.Now).AddSeconds(
                root.GetProperty("expires_in").GetDouble()));
    }
}

public static class CodexOAuthFlow
{
    public const string ClientId = "app_EMoamEEZ73f0CkXaXp7hrann";
    public const string AuthorizeEndpoint = "https://auth.openai.com/oauth/authorize";
    public const string TokenEndpoint = "https://auth.openai.com/oauth/token";
    public const string Scopes =
        "openid profile email offline_access api.connectors.read api.connectors.invoke";
    public const string Originator = "codex_cli_rs";

    public static string RedirectUri(int port) =>
        $"http://localhost:{port.ToString(CultureInfo.InvariantCulture)}/auth/callback";

    public static string AuthorizeUrl(
        Pkce pkce,
        string state,
        string redirectUri) =>
        OAuthHelpers.BuildUrl(
            AuthorizeEndpoint,
            new Dictionary<string, string>
            {
                ["response_type"] = "code",
                ["client_id"] = ClientId,
                ["redirect_uri"] = redirectUri,
                ["scope"] = Scopes,
                ["code_challenge"] = pkce.Challenge,
                ["code_challenge_method"] = "S256",
                ["id_token_add_organizations"] = "true",
                ["codex_cli_simplified_flow"] = "true",
                ["state"] = state,
                ["originator"] = Originator,
            });

    public static OAuthTokens ParseTokens(
        string json,
        DateTimeOffset? now = null)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var accessToken = root.GetProperty("access_token").GetString() ??
                          throw new JsonException("Missing access_token.");
        var refreshToken = root.TryGetProperty("refresh_token", out var refresh)
            ? refresh.GetString() ?? string.Empty
            : string.Empty;
        var accountId = root.TryGetProperty("id_token", out var idToken)
            ? AccountIdFromIdToken(idToken.GetString() ?? string.Empty)
            : null;
        return new OAuthTokens(
            accessToken,
            refreshToken,
            (now ?? DateTimeOffset.Now).AddSeconds(
                root.GetProperty("expires_in").GetDouble()),
            accountId);
    }

    public static string? AccountIdFromIdToken(string idToken)
    {
        var segments = idToken.Split('.');
        if (segments.Length < 2)
        {
            return null;
        }

        var payload = OAuthHelpers.DecodeBase64Url(segments[1]);
        if (payload is null)
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(payload);
            var root = document.RootElement;
            if (root.TryGetProperty("https://api.openai.com/auth", out var auth) &&
                auth.ValueKind == JsonValueKind.Object &&
                auth.TryGetProperty("chatgpt_account_id", out var nested))
            {
                return nested.GetString();
            }

            return root.TryGetProperty("chatgpt_account_id", out var direct)
                ? direct.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
