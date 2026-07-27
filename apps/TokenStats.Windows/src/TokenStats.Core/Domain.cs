namespace TokenStats.Core;

public enum AgentId
{
    ClaudeCode,
    Codex,
}

public enum SignInStyle
{
    PasteCode,
    SelfCompleting,
}

public enum GaugeStyle
{
    Dial,
    Ring,
    Bar,
}

public enum TodayMetricMode
{
    Token,
    Usage,
}

public sealed record GaugeSlot(string Label, bool Emphasized = false);

public sealed record AgentDefinition(
    AgentId Id,
    string DisplayName,
    string ShortLabel,
    SignInStyle SignInStyle,
    IReadOnlyList<GaugeSlot> GaugeSlots,
    string TranscriptRoot);

public static class AgentRegistry
{
    private static readonly string UserHome =
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    public static IReadOnlyList<AgentDefinition> All { get; } =
    [
        new(
            AgentId.ClaudeCode,
            "Claude Code",
            "C",
            SignInStyle.PasteCode,
            [
                new("Weekly"),
                new("5-hour", true),
                new("Fable"),
            ],
            Path.Combine(UserHome, ".claude", "projects")),
        new(
            AgentId.Codex,
            "Codex",
            "X",
            SignInStyle.SelfCompleting,
            [],
            Path.Combine(UserHome, ".codex", "sessions")),
    ];

    public static AgentDefinition Get(AgentId id) =>
        All.First(agent => agent.Id == id);
}

public enum UsageWindowKind
{
    Unknown,
    ShortTerm,
    Weekly,
}

public sealed record UsageWindow(
    string Label,
    double PercentConsumed,
    DateTimeOffset? ResetAt,
    UsageWindowKind Kind = UsageWindowKind.Unknown,
    long? DurationSeconds = null)
{
    public double PercentRemaining => Math.Clamp(100 - PercentConsumed, 0, 100);
}

public sealed record UsageSnapshot(IReadOnlyList<UsageWindow> Windows, DateTimeOffset FetchedAt);

public enum AgentStateKind
{
    SignedOut,
    Loading,
    Fresh,
    StaleDisclosed,
}

public sealed record AgentState(AgentStateKind Kind, UsageSnapshot? Snapshot = null)
{
    public static AgentState SignedOut { get; } = new(AgentStateKind.SignedOut);
    public static AgentState Loading { get; } = new(AgentStateKind.Loading);
    public static AgentState Fresh(UsageSnapshot snapshot) =>
        new(AgentStateKind.Fresh, snapshot);
    public static AgentState Stale(UsageSnapshot snapshot) =>
        new(AgentStateKind.StaleDisclosed, snapshot);
}

public enum AgentEventKind
{
    SignedOut,
    LoadingStarted,
    FetchSucceeded,
    FetchFailed,
}

public sealed record AgentEvent(AgentEventKind Kind, UsageSnapshot? Snapshot = null);

public static class AgentStateReducer
{
    public static AgentState Reduce(AgentState state, AgentEvent @event) =>
        @event.Kind switch
        {
            AgentEventKind.FetchSucceeded when @event.Snapshot is not null =>
                AgentState.Fresh(@event.Snapshot),
            AgentEventKind.FetchFailed when state.Snapshot is not null =>
                AgentState.Stale(state.Snapshot),
            AgentEventKind.SignedOut => AgentState.SignedOut,
            AgentEventKind.LoadingStarted when state.Snapshot is null =>
                AgentState.Loading,
            _ => state,
        };
}

public sealed record OAuthTokens(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    string? AccountId = null)
{
    public bool IsExpired(DateTimeOffset now) => now >= ExpiresAt.AddMinutes(-1);
}

public sealed record Pkce(string Verifier, string Challenge);

public sealed class UsageException : Exception
{
    public UsageException(string message) : base(message)
    {
    }

    public static UsageException NotSignedIn() => new("Not signed in.");

    public static UsageException BadResponse(int status, string body) =>
        new($"HTTP {status}. {body[..Math.Min(body.Length, 200)]}");

    public static UsageException NoWindows(string body) =>
        new($"Got data but no Usage Windows recognized. {body[..Math.Min(body.Length, 200)]}");
}

public readonly record struct TokenBreakdown(
    long RawInputTokens,
    long OutputTokens,
    long CacheWriteTokens,
    long CacheWrite1HourTokens,
    long CacheReadTokens)
{
    public long TokenMetricTotal =>
        RawInputTokens + CacheWriteTokens + CacheWrite1HourTokens + OutputTokens;

    public long MeteredTokenTotal => TokenMetricTotal + CacheReadTokens;

    public TokenBreakdown Add(TokenBreakdown other) => new(
        RawInputTokens + other.RawInputTokens,
        OutputTokens + other.OutputTokens,
        CacheWriteTokens + other.CacheWriteTokens,
        CacheWrite1HourTokens + other.CacheWrite1HourTokens,
        CacheReadTokens + other.CacheReadTokens);

    public static TokenBreakdown NonNegative(
        long rawInputTokens,
        long outputTokens,
        long cacheWriteTokens,
        long cacheWrite1HourTokens,
        long cacheReadTokens) => new(
        Math.Max(rawInputTokens, 0),
        Math.Max(outputTokens, 0),
        Math.Max(cacheWriteTokens, 0),
        Math.Max(cacheWrite1HourTokens, 0),
        Math.Max(cacheReadTokens, 0));
}

public sealed record ModelTokenUsage(
    AgentId AgentId,
    string? Model,
    TokenBreakdown Breakdown,
    int ResponseCount);

public sealed class TokenUsage
{
    private readonly Dictionary<ModelUsageKey, ModelUsageAccumulator> modelUsage = [];
    private long cacheWriteTokens;

    /// <summary>Non-cached input tokens.</summary>
    public long InputTokens { get; set; }
    public long OutputTokens { get; set; }

    /// <summary>Default/5-minute cache writes.</summary>
    public long CacheWriteTokens
    {
        get => cacheWriteTokens;
        set => cacheWriteTokens = value;
    }

    /// <summary>
    /// Backward-compatible name used by older callers and transcript fixtures.
    /// </summary>
    public long CacheCreationTokens
    {
        get => CacheWriteTokens;
        set => CacheWriteTokens = value;
    }

    public long CacheWrite1HourTokens { get; set; }
    public long CacheReadTokens { get; set; }
    public int ResponseCount { get; set; }

    /// <summary>
    /// The user-facing Token metric: raw input + cache writes + output.
    /// Cache reads are deliberately excluded.
    /// </summary>
    public long BillableTokens => Breakdown.TokenMetricTotal;

    /// <summary>Compatibility alias; now follows the explicit Token metric.</summary>
    public long TotalTokens => BillableTokens;

    public long MeteredTokens => Breakdown.MeteredTokenTotal;

    public TokenBreakdown Breakdown => new(
        InputTokens,
        OutputTokens,
        CacheWriteTokens,
        CacheWrite1HourTokens,
        CacheReadTokens);

    public IReadOnlyList<ModelTokenUsage> ModelUsage =>
        modelUsage
            .OrderBy(item => item.Key.AgentId)
            .ThenBy(item => item.Key.Model, StringComparer.OrdinalIgnoreCase)
            .Select(item => new ModelTokenUsage(
                item.Key.AgentId,
                item.Key.Model,
                item.Value.Breakdown,
                item.Value.ResponseCount))
            .ToArray();

    public void AddAttributed(
        AgentId agentId,
        string? model,
        TokenUsage response)
    {
        ArgumentNullException.ThrowIfNull(response);
        AddTotals(response);

        var key = new ModelUsageKey(agentId, NormalizeModel(model));
        if (!modelUsage.TryGetValue(key, out var accumulator))
        {
            accumulator = new ModelUsageAccumulator();
            modelUsage.Add(key, accumulator);
        }

        accumulator.Breakdown = accumulator.Breakdown.Add(response.Breakdown);
        accumulator.ResponseCount += response.ResponseCount;
    }

    public void Add(TokenUsage other)
    {
        ArgumentNullException.ThrowIfNull(other);
        AddTotals(other);
        foreach (var item in other.modelUsage)
        {
            if (!modelUsage.TryGetValue(item.Key, out var accumulator))
            {
                accumulator = new ModelUsageAccumulator();
                modelUsage.Add(item.Key, accumulator);
            }

            accumulator.Breakdown =
                accumulator.Breakdown.Add(item.Value.Breakdown);
            accumulator.ResponseCount += item.Value.ResponseCount;
        }
    }

    public TokenUsage Clone()
    {
        var clone = new TokenUsage
        {
            InputTokens = InputTokens,
            OutputTokens = OutputTokens,
            CacheWriteTokens = CacheWriteTokens,
            CacheWrite1HourTokens = CacheWrite1HourTokens,
            CacheReadTokens = CacheReadTokens,
            ResponseCount = ResponseCount,
        };
        foreach (var item in modelUsage)
        {
            clone.modelUsage.Add(
                item.Key,
                new ModelUsageAccumulator
                {
                    Breakdown = item.Value.Breakdown,
                    ResponseCount = item.Value.ResponseCount,
                });
        }

        return clone;
    }

    private static string? NormalizeModel(string? model) =>
        string.IsNullOrWhiteSpace(model)
            ? null
            : model.Trim().ToLowerInvariant();

    private void AddTotals(TokenUsage other)
    {
        InputTokens += other.InputTokens;
        OutputTokens += other.OutputTokens;
        CacheWriteTokens += other.CacheWriteTokens;
        CacheWrite1HourTokens += other.CacheWrite1HourTokens;
        CacheReadTokens += other.CacheReadTokens;
        ResponseCount += other.ResponseCount;
    }

    private readonly record struct ModelUsageKey(AgentId AgentId, string? Model);

    private sealed class ModelUsageAccumulator
    {
        public TokenBreakdown Breakdown { get; set; }
        public int ResponseCount { get; set; }
    }
}
