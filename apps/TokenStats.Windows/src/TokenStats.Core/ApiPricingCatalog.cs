namespace TokenStats.Core;

/// <summary>
/// Standard API list prices in USD per million tokens. These rates estimate
/// an API-equivalent value for local transcript usage; they are not a bill or
/// a conversion of a ChatGPT/Claude subscription.
/// </summary>
public sealed record ApiTokenRates(
    decimal RawInput,
    decimal CacheWrite,
    decimal CacheWrite1Hour,
    decimal CacheRead,
    decimal Output);

/// <summary>
/// The processing tier whose list price applies to a request. Transcript
/// readers currently do not persist the API response's service_tier, so the
/// estimator defaults to Standard until a verified tier is supplied.
/// </summary>
public enum ApiPricingMode
{
    Standard,
    Batch,
    Flex,
    Fast,
}

/// <summary>The short/long context pricing column selected for a request.</summary>
public enum ApiPricingContext
{
    Short,
    Long,
}

public sealed record ApiCostEstimate(
    decimal CostUsd,
    long PricedTokens,
    long UnpricedTokens,
    IReadOnlyList<string> UnpricedModels)
{
    public bool IsAvailable => PricedTokens > 0;
    public bool IsPartial => UnpricedTokens > 0;
}

public static class ApiPricingCatalog
{
    public static DateOnly LastReviewed { get; } = new(2026, 8, 4);

    public const string OpenAiPricingSource =
        "https://developers.openai.com/api/docs/pricing";

    public const string AnthropicPricingSource =
        "https://platform.claude.com/docs/en/about-claude/pricing";

    private static readonly PricingRule[] Rules =
    [
        // GPT-5.6 flagship prices are split by processing mode and context
        // length. Fast mode has no long-context price because OpenAI does not
        // support Fast mode for long-context requests.
        OpenAi(
            "gpt-5.6-sol",
            standardShort: OpenAiRates(5m, 6.25m, 0.50m, 30m),
            standardLong: OpenAiRates(10m, 12.50m, 1m, 45m),
            batchShort: OpenAiRates(2.50m, 3.125m, 0.25m, 15m),
            batchLong: OpenAiRates(5m, 6.25m, 0.50m, 22.50m),
            flexShort: OpenAiRates(2.50m, 3.125m, 0.25m, 15m),
            flexLong: OpenAiRates(5m, 6.25m, 0.50m, 22.50m),
            fastShort: OpenAiRates(10m, 12.50m, 1m, 60m)),
        OpenAi(
            "gpt-5.6-terra",
            standardShort: OpenAiRates(2m, 2.50m, 0.20m, 12m),
            standardLong: OpenAiRates(4m, 5m, 0.40m, 18m),
            batchShort: OpenAiRates(1m, 1.25m, 0.10m, 6m),
            batchLong: OpenAiRates(2m, 2.50m, 0.20m, 9m),
            flexShort: OpenAiRates(1m, 1.25m, 0.10m, 6m),
            flexLong: OpenAiRates(2m, 2.50m, 0.20m, 9m),
            fastShort: OpenAiRates(4m, 5m, 0.40m, 24m)),
        OpenAi(
            "gpt-5.6-luna",
            standardShort: OpenAiRates(0.20m, 0.25m, 0.02m, 1.20m),
            standardLong: OpenAiRates(0.40m, 0.50m, 0.04m, 1.80m),
            batchShort: OpenAiRates(0.10m, 0.125m, 0.01m, 0.60m),
            batchLong: OpenAiRates(0.20m, 0.25m, 0.02m, 0.90m),
            flexShort: OpenAiRates(0.10m, 0.125m, 0.01m, 0.60m),
            flexLong: OpenAiRates(0.20m, 0.25m, 0.02m, 0.90m),
            fastShort: OpenAiRates(0.40m, 0.50m, 0.04m, 2.40m)),
        OpenAi(
            "gpt-5.6",
            standardShort: OpenAiRates(5m, 6.25m, 0.50m, 30m),
            standardLong: OpenAiRates(10m, 12.50m, 1m, 45m),
            batchShort: OpenAiRates(2.50m, 3.125m, 0.25m, 15m),
            batchLong: OpenAiRates(5m, 6.25m, 0.50m, 22.50m),
            flexShort: OpenAiRates(2.50m, 3.125m, 0.25m, 15m),
            flexLong: OpenAiRates(5m, 6.25m, 0.50m, 22.50m),
            fastShort: OpenAiRates(10m, 12.50m, 1m, 60m)),
        OpenAi(
            "gpt-5.5",
            standardShort: OpenAiRates(5m, 0m, 0.50m, 30m),
            standardLong: OpenAiRates(10m, 0m, 1m, 45m),
            batchShort: OpenAiRates(2.50m, 0m, 0.25m, 15m),
            batchLong: OpenAiRates(5m, 0m, 0.50m, 22.50m),
            flexShort: OpenAiRates(2.50m, 0m, 0.25m, 15m),
            flexLong: OpenAiRates(5m, 0m, 0.50m, 22.50m),
            fastShort: OpenAiRates(12.50m, 0m, 1.25m, 75m)),
        OpenAi(
            "gpt-5.5-pro",
            standardShort: OpenAiRates(30m, 0m, 0m, 180m),
            standardLong: OpenAiRates(60m, 0m, 0m, 270m),
            batchShort: OpenAiRates(15m, 0m, 0m, 90m),
            flexShort: OpenAiRates(15m, 0m, 0m, 90m)),
        OpenAi(
            "gpt-5.4",
            standardShort: OpenAiRates(2.50m, 0m, 0.25m, 15m),
            standardLong: OpenAiRates(5m, 0m, 0.50m, 22.50m),
            batchShort: OpenAiRates(1.25m, 0m, 0.13m, 7.50m),
            batchLong: OpenAiRates(2.50m, 0m, 0.25m, 11.25m),
            flexShort: OpenAiRates(1.25m, 0m, 0.13m, 7.50m),
            flexLong: OpenAiRates(2.50m, 0m, 0.25m, 11.25m),
            fastShort: OpenAiRates(5m, 0m, 0.50m, 30m)),
        OpenAi(
            "gpt-5.4-mini",
            standardShort: OpenAiRates(0.75m, 0m, 0.075m, 4.50m),
            batchShort: OpenAiRates(0.375m, 0m, 0.0375m, 2.25m),
            flexShort: OpenAiRates(0.375m, 0m, 0.0375m, 2.25m),
            fastShort: OpenAiRates(1.50m, 0m, 0.15m, 9m)),
        OpenAi(
            "gpt-5.4-nano",
            standardShort: OpenAiRates(0.20m, 0m, 0.02m, 1.25m),
            batchShort: OpenAiRates(0.10m, 0m, 0.01m, 0.625m),
            flexShort: OpenAiRates(0.10m, 0m, 0.01m, 0.625m)),
        OpenAi(
            "gpt-5.4-pro",
            standardShort: OpenAiRates(30m, 0m, 0m, 180m),
            standardLong: OpenAiRates(60m, 0m, 0m, 270m),
            batchShort: OpenAiRates(15m, 0m, 0m, 90m),
            batchLong: OpenAiRates(30m, 0m, 0m, 135m),
            flexShort: OpenAiRates(15m, 0m, 0m, 90m),
            flexLong: OpenAiRates(30m, 0m, 0m, 135m)),

        // Legacy OpenAI models retain Standard/short coverage. Their current
        // pricing table does not list cache-write charges, so those rates are
        // explicitly zero rather than inheriting the GPT-5.6 multiplier.
        OpenAi("gpt-5.3-codex", 1.75m, 0m, 0.175m, 14m),
        OpenAi("gpt-5.2-codex", 1.75m, 0m, 0.175m, 14m),
        OpenAi("gpt-5.2", 1.75m, 0m, 0.175m, 14m),
        OpenAi("gpt-5.1-codex-mini", 0.25m, 0m, 0.025m, 2m),
        OpenAi("gpt-5.1-codex-max", 1.25m, 0m, 0.125m, 10m),
        OpenAi("gpt-5.1-codex", 1.25m, 0m, 0.125m, 10m),
        OpenAi("gpt-5.1", 1.25m, 0m, 0.125m, 10m),
        OpenAi("gpt-5-codex", 1.25m, 0m, 0.125m, 10m),
        OpenAi("gpt-5", 1.25m, 0m, 0.125m, 10m),
        OpenAi("codex-mini-latest", 1.50m, 0m, 0.375m, 6m),

        Anthropic("claude-fable-5", 10m, 12.50m, 20m, 1m, 50m),
        Anthropic("claude-mythos-5", 10m, 12.50m, 20m, 1m, 50m),
        Anthropic("claude-opus-5", 5m, 6.25m, 10m, 0.50m, 25m),
        Anthropic("claude-opus-4-8", 5m, 6.25m, 10m, 0.50m, 25m),
        Anthropic("claude-opus-4-7", 5m, 6.25m, 10m, 0.50m, 25m),
        Anthropic("claude-opus-4-6", 5m, 6.25m, 10m, 0.50m, 25m),
        Anthropic("claude-opus-4-5", 5m, 6.25m, 10m, 0.50m, 25m),
        Anthropic("claude-opus-4-1", 15m, 18.75m, 30m, 1.50m, 75m),
        Anthropic("claude-opus-4", 15m, 18.75m, 30m, 1.50m, 75m),

        // Sonnet 5 has an introductory list price through 2026-08-31.
        Anthropic(
            "claude-sonnet-5",
            2m,
            2.50m,
            4m,
            0.20m,
            10m,
            untilExclusive: new DateOnly(2026, 9, 1)),
        Anthropic(
            "claude-sonnet-5",
            3m,
            3.75m,
            6m,
            0.30m,
            15m,
            fromInclusive: new DateOnly(2026, 9, 1)),
        Anthropic("claude-sonnet-4-6", 3m, 3.75m, 6m, 0.30m, 15m),
        Anthropic("claude-sonnet-4-5", 3m, 3.75m, 6m, 0.30m, 15m),
        Anthropic("claude-sonnet-4", 3m, 3.75m, 6m, 0.30m, 15m),
        Anthropic("claude-3-7-sonnet", 3m, 3.75m, 6m, 0.30m, 15m),
        Anthropic("claude-3-5-sonnet", 3m, 3.75m, 6m, 0.30m, 15m),
        Anthropic("claude-haiku-4-5", 1m, 1.25m, 2m, 0.10m, 5m),
        Anthropic("claude-3-5-haiku", 0.80m, 1m, 1.60m, 0.08m, 4m),
        Anthropic("claude-3-haiku", 0.25m, 0.3125m, 0.50m, 0.025m, 1.25m),
        Anthropic("claude-3-opus", 15m, 18.75m, 30m, 1.50m, 75m),
    ];

    public static ApiCostEstimate Estimate(
        TokenUsage usage,
        DateOnly? pricingDate = null,
        TokenKindSelection selection = TokenKindSelection.All,
        ApiPricingMode pricingMode = ApiPricingMode.Standard,
        ApiPricingContext pricingContext = ApiPricingContext.Short)
    {
        ArgumentNullException.ThrowIfNull(usage);
        if (!selection.IsValid())
        {
            throw new ArgumentOutOfRangeException(
                nameof(selection),
                selection,
                "The selection contains an unknown Token Kind.");
        }

        var date = pricingDate ?? DateOnly.FromDateTime(DateTime.Today);
        var cost = 0m;
        long pricedTokens = 0;
        long unpricedTokens = 0;
        var unpricedModels = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var attributed = new TokenBreakdown();

        foreach (var item in usage.ModelUsage)
        {
            attributed = attributed.Add(item.Breakdown);
            var selectedTokens = item.Breakdown.SelectedTotal(selection);
            if (selectedTokens == 0)
            {
                continue;
            }

            if (item.Model is not null &&
                TryResolve(
                    item.AgentId,
                    item.Model,
                    date,
                    out var rates,
                    pricingMode,
                    pricingContext))
            {
                cost += Cost(item.Breakdown, rates, selection);
                pricedTokens += selectedTokens;
                continue;
            }

            unpricedTokens += selectedTokens;
            unpricedModels.Add(
                $"{AgentRegistry.Get(item.AgentId).DisplayName}: " +
                (item.Model ?? "unknown model"));
        }

        var unattributed = SubtractNonNegative(usage.Breakdown, attributed);
        var selectedUnattributed = unattributed.SelectedTotal(selection);
        if (selectedUnattributed > 0)
        {
            unpricedTokens += selectedUnattributed;
            unpricedModels.Add("unknown transcript model");
        }

        return new ApiCostEstimate(
            cost,
            pricedTokens,
            unpricedTokens,
            unpricedModels.Order(StringComparer.OrdinalIgnoreCase).ToArray());
    }

    public static bool TryResolve(
        AgentId agentId,
        string model,
        DateOnly pricingDate,
        out ApiTokenRates rates,
        ApiPricingMode pricingMode = ApiPricingMode.Standard,
        ApiPricingContext pricingContext = ApiPricingContext.Short)
    {
        rates = null!;
        if (string.IsNullOrWhiteSpace(model))
        {
            return false;
        }

        var rule = Rules
            .Where(item =>
                item.AgentId == agentId &&
                MatchesModel(item.ModelPrefix, model) &&
                (!item.FromInclusive.HasValue ||
                 pricingDate >= item.FromInclusive.Value) &&
                (!item.UntilExclusive.HasValue ||
                 pricingDate < item.UntilExclusive.Value))
            .OrderByDescending(item => item.ModelPrefix.Length)
            .FirstOrDefault();
        if (rule is null)
        {
            return false;
        }

        var variant = rule.Variants.FirstOrDefault(item =>
            item.Mode == pricingMode &&
            item.Context == pricingContext);
        if (variant is null)
        {
            return false;
        }

        rates = variant.Rates;
        return true;
    }

    private static bool MatchesModel(string modelPrefix, string model)
    {
        if (string.Equals(
                modelPrefix,
                model,
                StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (!model.StartsWith(
                modelPrefix + "-",
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        // Accept dated snapshots of a known model, but do not silently price
        // an unknown named variant (for example a future "-spark" tier).
        var suffix = model[(modelPrefix.Length + 1)..];
        return suffix.StartsWith("20", StringComparison.Ordinal) &&
               suffix.All(character =>
                   char.IsAsciiDigit(character) || character == '-');
    }

    private static decimal Cost(
        TokenBreakdown usage,
        ApiTokenRates rates,
        TokenKindSelection selection)
    {
        var cost = 0m;
        if (selection.Includes(TokenKind.DirectInput))
        {
            cost += usage.RawInputTokens * rates.RawInput;
        }

        if (selection.Includes(TokenKind.Output))
        {
            cost += usage.OutputTokens * rates.Output;
        }

        if (selection.Includes(TokenKind.CacheWrite))
        {
            cost += usage.CacheWriteTokens * rates.CacheWrite;
            cost += usage.CacheWrite1HourTokens * rates.CacheWrite1Hour;
        }

        if (selection.Includes(TokenKind.CacheRead))
        {
            cost += usage.CacheReadTokens * rates.CacheRead;
        }

        return cost / 1_000_000m;
    }

    private static TokenBreakdown SubtractNonNegative(
        TokenBreakdown total,
        TokenBreakdown attributed) =>
        TokenBreakdown.NonNegative(
            total.RawInputTokens - attributed.RawInputTokens,
            total.OutputTokens - attributed.OutputTokens,
            total.CacheWriteTokens - attributed.CacheWriteTokens,
            total.CacheWrite1HourTokens - attributed.CacheWrite1HourTokens,
            total.CacheReadTokens - attributed.CacheReadTokens);

    private static PricingRule OpenAi(
        string modelPrefix,
        decimal rawInput,
        decimal cacheWrite,
        decimal cacheRead,
        decimal output) =>
        OpenAi(
            modelPrefix,
            OpenAiRates(rawInput, cacheWrite, cacheRead, output));

    private static PricingRule OpenAi(
        string modelPrefix,
        ApiTokenRates standardShort,
        ApiTokenRates? standardLong = null,
        ApiTokenRates? batchShort = null,
        ApiTokenRates? batchLong = null,
        ApiTokenRates? flexShort = null,
        ApiTokenRates? flexLong = null,
        ApiTokenRates? fastShort = null)
    {
        var variants = new List<PricingVariant>
        {
            new(ApiPricingMode.Standard, ApiPricingContext.Short, standardShort),
        };
        AddVariant(
            variants,
            ApiPricingMode.Standard,
            ApiPricingContext.Long,
            standardLong);
        AddVariant(
            variants,
            ApiPricingMode.Batch,
            ApiPricingContext.Short,
            batchShort);
        AddVariant(
            variants,
            ApiPricingMode.Batch,
            ApiPricingContext.Long,
            batchLong);
        AddVariant(
            variants,
            ApiPricingMode.Flex,
            ApiPricingContext.Short,
            flexShort);
        AddVariant(
            variants,
            ApiPricingMode.Flex,
            ApiPricingContext.Long,
            flexLong);
        AddVariant(
            variants,
            ApiPricingMode.Fast,
            ApiPricingContext.Short,
            fastShort);

        return new(
            AgentId.Codex,
            modelPrefix,
            variants,
            null,
            null);
    }

    private static void AddVariant(
        ICollection<PricingVariant> variants,
        ApiPricingMode mode,
        ApiPricingContext context,
        ApiTokenRates? rates)
    {
        if (rates is not null)
        {
            variants.Add(new(mode, context, rates));
        }
    }

    private static ApiTokenRates OpenAiRates(
        decimal rawInput,
        decimal cacheWrite,
        decimal cacheRead,
        decimal output) =>
        new(
            rawInput,
            cacheWrite,
            cacheWrite,
            cacheRead,
            output);

    private static PricingRule Anthropic(
        string modelPrefix,
        decimal rawInput,
        decimal cacheWrite,
        decimal cacheWrite1Hour,
        decimal cacheRead,
        decimal output,
        DateOnly? fromInclusive = null,
        DateOnly? untilExclusive = null) =>
        new(
            AgentId.ClaudeCode,
            modelPrefix,
            [
                new(
                    ApiPricingMode.Standard,
                    ApiPricingContext.Short,
                    new ApiTokenRates(
                        rawInput,
                        cacheWrite,
                        cacheWrite1Hour,
                        cacheRead,
                        output)),
            ],
            fromInclusive,
            untilExclusive);

    private sealed record PricingRule(
        AgentId AgentId,
        string ModelPrefix,
        IReadOnlyList<PricingVariant> Variants,
        DateOnly? FromInclusive,
        DateOnly? UntilExclusive);

    private sealed record PricingVariant(
        ApiPricingMode Mode,
        ApiPricingContext Context,
        ApiTokenRates Rates);
}
