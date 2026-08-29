namespace TokenStats.Core;

public enum AgentId
{
    ClaudeCode,
    Codex,
    Cursor,
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
    // Names are retained for settings-file compatibility. The user-facing
    // labels are Billing tokens and API equivalent.
    Token,
    Usage,
}

/// <summary>
/// Local-calendar ranges shown by the Token Odometer. Today is inclusive and
/// the range is deliberately capped at 30 days because Claude Code prunes
/// transcript history sooner than Codex.
/// </summary>
public enum TokenRange
{
    Today,
    SevenDays,
    ThirtyDays,
}

public static class TokenRangeExtensions
{
    public static int Days(this TokenRange range) =>
        range switch
        {
            TokenRange.Today => 1,
            TokenRange.SevenDays => 7,
            TokenRange.ThirtyDays => 30,
            _ => throw new ArgumentOutOfRangeException(nameof(range), range, null),
        };

    public static string Label(this TokenRange range) =>
        range switch
        {
            TokenRange.Today => "Today",
            TokenRange.SevenDays => "7 days",
            TokenRange.ThirtyDays => "30 days",
            _ => throw new ArgumentOutOfRangeException(nameof(range), range, null),
        };

    /// <summary>
    /// The first local calendar date in the range. Date arithmetic, instead of
    /// subtracting 86,400-second intervals, keeps daylight-saving boundaries
    /// on the intended local date.
    /// </summary>
    public static DateOnly StartDate(
        this TokenRange range,
        DateTimeOffset now,
        TimeZoneInfo localTimeZone)
    {
        ArgumentNullException.ThrowIfNull(localTimeZone);
        var localNow = TimeZoneInfo.ConvertTime(now, localTimeZone);
        return DateOnly
            .FromDateTime(localNow.DateTime)
            .AddDays(-(range.Days() - 1));
    }
}

/// <summary>
/// The three supported columns in the Token Odometer, in display order.
/// Provider cache-write fields are intentionally not represented as a Token
/// Kind because their read path is not worth the feature's cost.
/// </summary>
public enum TokenKind
{
    DirectInput,
    Output,
    CacheRead,
}

[Flags]
public enum TokenKindSelection
{
    None = 0,
    DirectInput = 1 << 0,
    Output = 1 << 1,
    CacheRead = 1 << 2,
    All = DirectInput | Output | CacheRead,
}

public enum TokenValueDisplayMode
{
    Value,
    Percentage,
    ValueAndPercentage,
}

public static class TokenKindSelectionExtensions
{
    public static bool IsValid(
        this TokenKindSelection selection,
        bool allowNone = true) =>
        (selection & ~TokenKindSelection.All) == 0 &&
        (allowNone || selection != TokenKindSelection.None);

    public static bool Includes(
        this TokenKindSelection selection,
        TokenKind kind)
    {
        if (!selection.IsValid())
        {
            throw new ArgumentOutOfRangeException(
                nameof(selection),
                selection,
                "The selection contains an unknown Token Kind.");
        }

        var flag = kind switch
        {
            TokenKind.DirectInput => TokenKindSelection.DirectInput,
            TokenKind.Output => TokenKindSelection.Output,
            TokenKind.CacheRead => TokenKindSelection.CacheRead,
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, null),
        };
        return (selection & flag) != 0;
    }
}

/// <summary>
/// A transcript-reported model name. Unattributed is a distinct value rather
/// than the string "unknown", because an agent can genuinely name a model
/// "unknown".
/// </summary>
public readonly record struct ModelName : IComparable<ModelName>
{
    private ModelName(string? value)
    {
        Value = value;
    }

    public string? Value { get; }
    public bool IsUnattributed => Value is null;
    public string DisplayName => Value ?? "unknown";

    public static ModelName Unattributed => default;

    public static ModelName Named(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        return new ModelName(value.Trim());
    }

    public static ModelName FromNullable(string? value) =>
        string.IsNullOrWhiteSpace(value)
            ? Unattributed
            : Named(value);

    public int CompareTo(ModelName other)
    {
        var displayComparison = StringComparer.Ordinal.Compare(
            DisplayName,
            other.DisplayName);
        if (displayComparison != 0)
        {
            return displayComparison;
        }

        // Keep the two values deterministic even when a real model is named
        // "unknown" and therefore shares the unattributed display label.
        return IsUnattributed.CompareTo(other.IsUnattributed);
    }

    public override string ToString() => DisplayName;
}

public sealed record GaugeSlot(string Label, bool Emphasized = false);

public sealed record AgentTranscriptRoot(
    AgentId Id,
    string Label,
    string Path);

public sealed record AgentDefinition(
    AgentId Id,
    string DisplayName,
    string ShortLabel,
    SignInStyle SignInStyle,
    IReadOnlyList<GaugeSlot> GaugeSlots,
    string? TranscriptRoot);

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
        new(
            AgentId.Cursor,
            "Cursor",
            "R",
            SignInStyle.SelfCompleting,
            [],
            null),
    ];

    public static IReadOnlyList<AgentTranscriptRoot> TranscriptRoots { get; } =
        All.Select(definition => definition.TranscriptRoot is { } path
            ? new AgentTranscriptRoot(definition.Id, definition.DisplayName, path)
            : null)
            .OfType<AgentTranscriptRoot>()
            .ToArray();

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

/// <summary>
/// Online authentication health is deliberately separate from credential
/// presence and cached usage. A stored token starts in Checking; only an
/// accepted refresh or provider request can make the session Valid.
/// </summary>
public enum AuthSessionStateKind
{
    SignedOut,
    Checking,
    Valid,
    TemporarilyUnverifiable,
    ReauthenticationRequired,
}

public enum OAuthRefreshFailureReason
{
    Expired,
    Reused,
    Revoked,
    InvalidGrant,
    Unauthorized,
    Other,
}

public sealed record AuthSessionState(
    AuthSessionStateKind Kind,
    DateTimeOffset? LastValidatedAt = null,
    OAuthRefreshFailureReason? ReauthenticationReason = null,
    string? Diagnostic = null)
{
    public static AuthSessionState SignedOut { get; } =
        new(AuthSessionStateKind.SignedOut);

    public static AuthSessionState Checking(DateTimeOffset? lastValidatedAt = null) =>
        new(AuthSessionStateKind.Checking, lastValidatedAt);

    public static AuthSessionState Valid(
        DateTimeOffset validatedAt,
        string? diagnostic = null) =>
        new(AuthSessionStateKind.Valid, validatedAt, Diagnostic: diagnostic);

    public static AuthSessionState TemporarilyUnverifiable(
        DateTimeOffset? lastValidatedAt,
        string diagnostic) =>
        new(
            AuthSessionStateKind.TemporarilyUnverifiable,
            lastValidatedAt,
            Diagnostic: diagnostic);

    public static AuthSessionState ReauthenticationRequired(
        OAuthRefreshFailureReason reason,
        string diagnostic) =>
        new(
            AuthSessionStateKind.ReauthenticationRequired,
            ReauthenticationReason: reason,
            Diagnostic: diagnostic);
}

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

public enum CredentialPresence
{
    Present,
    Absent,
    TemporarilyUnavailable,
}

public sealed record Pkce(string Verifier, string Challenge);

public sealed class UsageException : Exception
{
    public UsageException(string message, int? statusCode = null) : base(message)
    {
        StatusCode = statusCode;
    }

    public int? StatusCode { get; }

    public static UsageException NotSignedIn() => new("Not signed in.");

    public static UsageException BadResponse(int status, string body) =>
        new(
            $"HTTP {status}. {body[..Math.Min(body.Length, 200)]}",
            status);

    public static UsageException NoWindows(string body) =>
        new($"Got data but no Usage Windows recognized. {body[..Math.Min(body.Length, 200)]}");
}

/// <summary>
/// A sanitized OAuth refresh failure. The response body is intentionally not
/// retained: token-endpoint payloads must never flow into diagnostics or UI.
/// </summary>
public sealed class OAuthRefreshException : Exception
{
    public OAuthRefreshException(
        int statusCode,
        string? errorCode,
        OAuthRefreshFailureReason reason,
        bool isTerminal)
        : base(BuildMessage(statusCode, errorCode, reason, isTerminal))
    {
        StatusCode = statusCode;
        ErrorCode = errorCode;
        Reason = reason;
        IsTerminal = isTerminal;
    }

    public int StatusCode { get; }
    public string? ErrorCode { get; }
    public OAuthRefreshFailureReason Reason { get; }
    public bool IsTerminal { get; }

    private static string BuildMessage(
        int statusCode,
        string? errorCode,
        OAuthRefreshFailureReason reason,
        bool isTerminal)
    {
        var classification = isTerminal ? "terminal" : "transient";
        var code = string.IsNullOrWhiteSpace(errorCode)
            ? string.Empty
            : $", code {errorCode}";
        return $"OAuth refresh failed ({classification}, HTTP {statusCode}{code}, {reason}).";
    }
}

public sealed class TokenPersistenceException : Exception
{
    public TokenPersistenceException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// The refresh grant was accepted and any returned rotation was adopted, but
/// the resulting credential set still has no usable access bearer. This is
/// session-validity proof, not a terminal authentication rejection.
/// </summary>
public sealed class RefreshedAccessTokenUnavailableException : Exception
{
    public RefreshedAccessTokenUnavailableException(bool persistenceFailed)
        : base(persistenceFailed
            ? "The session refresh was accepted, but it returned no usable access token and the rotated credentials could not be saved."
            : "The session refresh was accepted, but it returned no usable access token.")
    {
        PersistenceFailed = persistenceFailed;
    }

    public bool PersistenceFailed { get; }
}

public readonly record struct TokenBreakdown(
    long RawInputTokens,
    long OutputTokens,
    long CacheReadTokens)
{
    public long TokenMetricTotal => RawInputTokens + OutputTokens;

    public long MeteredTokenTotal => TokenMetricTotal + CacheReadTokens;

    public long Amount(TokenKind kind) =>
        kind switch
        {
            TokenKind.DirectInput => RawInputTokens,
            TokenKind.Output => OutputTokens,
            TokenKind.CacheRead => CacheReadTokens,
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, null),
        };

    public long SelectedTotal(TokenKindSelection selection)
    {
        if (!selection.IsValid())
        {
            throw new ArgumentOutOfRangeException(
                nameof(selection),
                selection,
                "The selection contains an unknown Token Kind.");
        }

        var total = 0L;
        if (selection.Includes(TokenKind.DirectInput))
        {
            total += RawInputTokens;
        }

        if (selection.Includes(TokenKind.Output))
        {
            total += OutputTokens;
        }

        if (selection.Includes(TokenKind.CacheRead))
        {
            total += CacheReadTokens;
        }

        return total;
    }

    public TokenBreakdown Add(TokenBreakdown other) => new(
        RawInputTokens + other.RawInputTokens,
        OutputTokens + other.OutputTokens,
        CacheReadTokens + other.CacheReadTokens);

    public static TokenBreakdown NonNegative(
        long rawInputTokens,
        long outputTokens,
        long cacheReadTokens) => new(
        Math.Max(rawInputTokens, 0),
        Math.Max(outputTokens, 0),
        Math.Max(cacheReadTokens, 0));
}

public sealed record ModelTokenUsage(
    AgentId AgentId,
    ModelName Name,
    TokenBreakdown Breakdown,
    int ResponseCount)
{
    /// <summary>Backward-compatible nullable model value for pricing/UI code.</summary>
    public string? Model => Name.Value;
}

public sealed record DatedModelTokenUsage(
    DateOnly Day,
    AgentId AgentId,
    ModelName Name,
    TokenBreakdown Breakdown,
    int ResponseCount)
{
    public string? Model => Name.Value;
}

public sealed class TokenUsage
{
    private readonly Dictionary<ModelUsageKey, ModelUsageAccumulator> modelUsage = [];
    private readonly Dictionary<DatedModelUsageKey, ModelUsageAccumulator>
        datedModelUsage = [];

    /// <summary>Non-cached input tokens.</summary>
    public long InputTokens { get; set; }
    public long OutputTokens { get; set; }

    public long CacheReadTokens { get; set; }
    public int ResponseCount { get; set; }

    /// <summary>
    /// The user-facing Billing tokens metric:
    /// direct input + output.
    /// Cache reads are deliberately excluded.
    /// </summary>
    public long BillableTokens => Breakdown.TokenMetricTotal;

    /// <summary>Compatibility alias; now follows the explicit Token metric.</summary>
    public long TotalTokens => BillableTokens;

    public long MeteredTokens => Breakdown.MeteredTokenTotal;

    /// <summary>
    /// Token Odometer total. Unlike the existing user-facing Token metric, all
    /// three Odometer columns, including cache reads, contribute.
    /// </summary>
    public long OdometerTokens => MeteredTokens;

    public TokenBreakdown Breakdown => new(
        InputTokens,
        OutputTokens,
        CacheReadTokens);

    public long Amount(TokenKind kind) => Breakdown.Amount(kind);

    public long SelectedTotal(TokenKindSelection selection) =>
        Breakdown.SelectedTotal(selection);

    public IReadOnlyList<ModelTokenUsage> ModelUsage =>
        modelUsage
            .OrderBy(item => item.Key.AgentId)
            .ThenByDescending(item => item.Value.Breakdown.MeteredTokenTotal)
            .ThenBy(item => item.Key.Name)
            .Select(item => new ModelTokenUsage(
                item.Key.AgentId,
                item.Key.Name,
                item.Value.Breakdown,
                item.Value.ResponseCount))
            .ToArray();

    /// <summary>
    /// The same model attribution with the local occurrence day retained for
    /// effective-dated price selection. Parser cache state remains disposable;
    /// this is an in-process projection of the current transcript truth.
    /// </summary>
    public IReadOnlyList<DatedModelTokenUsage> DatedModelUsage =>
        datedModelUsage
            .OrderBy(item => item.Key.Day)
            .ThenBy(item => item.Key.AgentId)
            .ThenBy(item => item.Key.Name)
            .Select(item => new DatedModelTokenUsage(
                item.Key.Day,
                item.Key.AgentId,
                item.Key.Name,
                item.Value.Breakdown,
                item.Value.ResponseCount))
            .ToArray();

    public void AddAttributed(
        AgentId agentId,
        string? model,
        TokenUsage response)
    {
        AddAttributed(agentId, ModelName.FromNullable(model), response);
    }

    public void AddAttributed(
        AgentId agentId,
        ModelName model,
        TokenUsage response)
    {
        ArgumentNullException.ThrowIfNull(response);
        AddTotals(response);

        AddAttribution(agentId, model, response);
    }

    /// <summary>
    /// Adds only a model bucket, without adding the response to the aggregate
    /// totals. The transcript reader uses this to settle pending attribution
    /// after the response has already contributed to its day/file total.
    /// </summary>
    internal void AddAttribution(
        AgentId agentId,
        ModelName model,
        TokenUsage response)
    {
        ArgumentNullException.ThrowIfNull(response);
        var key = new ModelUsageKey(agentId, model);
        if (!modelUsage.TryGetValue(key, out var accumulator))
        {
            accumulator = new ModelUsageAccumulator();
            modelUsage.Add(key, accumulator);
        }

        accumulator.Breakdown = accumulator.Breakdown.Add(response.Breakdown);
        accumulator.ResponseCount += response.ResponseCount;
    }

    internal void AddDated(DateOnly day, TokenUsage other)
    {
        ArgumentNullException.ThrowIfNull(other);
        Add(other);
        foreach (var item in other.modelUsage)
        {
            AddDatedAccumulator(
                new DatedModelUsageKey(day, item.Key.AgentId, item.Key.Name),
                item.Value.Breakdown,
                item.Value.ResponseCount);
        }
    }

    internal void AddDatedAttribution(
        DateOnly day,
        AgentId agentId,
        ModelName model,
        TokenUsage response)
    {
        ArgumentNullException.ThrowIfNull(response);
        AddDatedAccumulator(
            new DatedModelUsageKey(day, agentId, model),
            response.Breakdown,
            response.ResponseCount);
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
        foreach (var item in other.datedModelUsage)
        {
            AddDatedAccumulator(
                item.Key,
                item.Value.Breakdown,
                item.Value.ResponseCount);
        }
    }

    public TokenUsage Clone()
    {
        var clone = new TokenUsage
        {
            InputTokens = InputTokens,
            OutputTokens = OutputTokens,
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
        foreach (var item in datedModelUsage)
        {
            clone.datedModelUsage.Add(
                item.Key,
                new ModelUsageAccumulator
                {
                    Breakdown = item.Value.Breakdown,
                    ResponseCount = item.Value.ResponseCount,
                });
        }

        return clone;
    }

    private void AddDatedAccumulator(
        DatedModelUsageKey key,
        TokenBreakdown breakdown,
        int responseCount)
    {
        if (!datedModelUsage.TryGetValue(key, out var accumulator))
        {
            accumulator = new ModelUsageAccumulator();
            datedModelUsage.Add(key, accumulator);
        }

        accumulator.Breakdown = accumulator.Breakdown.Add(breakdown);
        accumulator.ResponseCount += responseCount;
    }

    private void AddTotals(TokenUsage other)
    {
        InputTokens += other.InputTokens;
        OutputTokens += other.OutputTokens;
        CacheReadTokens += other.CacheReadTokens;
        ResponseCount += other.ResponseCount;
    }

    private readonly record struct ModelUsageKey(AgentId AgentId, ModelName Name);

    private readonly record struct DatedModelUsageKey(
        DateOnly Day,
        AgentId AgentId,
        ModelName Name);

    private sealed class ModelUsageAccumulator
    {
        public TokenBreakdown Breakdown { get; set; }
        public int ResponseCount { get; set; }
    }
}
