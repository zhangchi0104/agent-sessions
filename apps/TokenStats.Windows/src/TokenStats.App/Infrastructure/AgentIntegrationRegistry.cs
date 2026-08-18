using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using TokenStats.Core;

namespace TokenStats.App.Infrastructure;

internal sealed record AgentBrand(byte Red, byte Green, byte Blue);

internal sealed record AgentRuntime(
    IAgentAuthSession Auth,
    IUsageProvider Provider);

internal sealed record AgentIntegration(
    AgentDefinition Definition,
    AgentBrand Brand,
    Func<HttpClient, OAuthHttpClient, AgentRuntime> CreateRuntime);

internal sealed record AgentRuntimeSet(
    IReadOnlyDictionary<AgentId, IAgentAuthSession> Auth,
    IReadOnlyDictionary<AgentId, IUsageProvider> Providers);

/// <summary>
/// App-owned facts that cannot live in TokenStats.Core. AgentRegistry remains
/// the pure domain catalog; this registry is the single place that binds each
/// definition to its visual brand, credential store, auth flow, and provider.
/// </summary>
internal static class AgentIntegrationRegistry
{
    internal static IReadOnlyList<AgentIntegration> All { get; } =
    [
        new(
            AgentRegistry.Get(AgentId.ClaudeCode),
            new AgentBrand(0xD8, 0x78, 0x57),
            CreateClaudeCode),
        new(
            AgentRegistry.Get(AgentId.Codex),
            new AgentBrand(0x0A, 0xA3, 0x80),
            CreateCodex),
        new(
            AgentRegistry.Get(AgentId.Cursor),
            new AgentBrand(0x5C, 0x52, 0xC7),
            CreateCursor),
    ];

    private static readonly IReadOnlyDictionary<AgentId, AgentIntegration> ById =
        All.ToDictionary(integration => integration.Definition.Id);

    static AgentIntegrationRegistry()
    {
        var domainIds = AgentRegistry.All.Select(definition => definition.Id).ToHashSet();
        if (!domainIds.SetEquals(ById.Keys))
        {
            throw new InvalidOperationException(
                "Agent integration registry must cover every domain agent exactly once.");
        }
    }

    internal static AgentIntegration Get(AgentId id) => ById[id];

    internal static AgentRuntimeSet CreateRuntimeSet(HttpClient httpClient)
    {
        var oauthClient = new OAuthHttpClient(httpClient);
        var runtimes = All.ToDictionary(
            integration => integration.Definition.Id,
            integration => integration.CreateRuntime(httpClient, oauthClient));
        return new AgentRuntimeSet(
            runtimes.ToDictionary(item => item.Key, item => item.Value.Auth),
            runtimes.ToDictionary(item => item.Key, item => item.Value.Provider));
    }

    private static AgentRuntime CreateClaudeCode(
        HttpClient httpClient,
        OAuthHttpClient oauthClient)
    {
        var auth = new ClaudeAuthSession(
            new CredentialTokenStore("claude"),
            oauthClient);
        return new AgentRuntime(
            auth,
            new ClaudeUsageProvider(httpClient, auth.ValidAccessTokenAsync));
    }

    private static AgentRuntime CreateCodex(
        HttpClient httpClient,
        OAuthHttpClient oauthClient)
    {
        var auth = new CodexAuthSession(
            new CredentialTokenStore("codex"),
            oauthClient);
        return new AgentRuntime(
            auth,
            new CodexUsageProvider(
                httpClient,
                auth.ValidAccessTokenAsync,
                () => auth.AccountId));
    }

    private static AgentRuntime CreateCursor(
        HttpClient httpClient,
        OAuthHttpClient oauthClient)
    {
        var auth = new CursorAuthSession(
            new CredentialTokenStore("cursor"),
            oauthClient);
        return new AgentRuntime(
            auth,
            new CursorUsageProvider(httpClient, auth.ValidAccessTokenAsync));
    }
}
