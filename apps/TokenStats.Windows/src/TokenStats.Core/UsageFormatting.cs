using System.Globalization;

namespace TokenStats.Core;

public static class UsageFormatting
{
    public static string RemainingPercent(double percent) =>
        $"{(int)Math.Floor(Math.Clamp(percent, 0, 100))}%";

    public static string MenuBarText(AgentState state)
    {
        if (state.Kind == AgentStateKind.SignedOut)
        {
            return "—";
        }

        if (state.Kind == AgentStateKind.Loading)
        {
            return "…";
        }

        return SummaryWindow(state.Snapshot) is { } primary
            ? RemainingPercent(primary.PercentRemaining)
            : "—";
    }

    public static string TraySummary(
        IEnumerable<(AgentDefinition Definition, AgentState State)> agents)
    {
        var visible = agents
            .Where(item => item.State.Kind != AgentStateKind.SignedOut)
            .ToList();

        return visible.Count switch
        {
            0 => "—",
            1 => MenuBarText(visible[0].State),
            _ => string.Join(
                " ",
                visible.Select(item =>
                    $"{item.Definition.ShortLabel}: {MenuBarText(item.State)}")),
        };
    }

    public static string CompactDuration(
        DateTimeOffset resetAt,
        DateTimeOffset? now = null)
    {
        var remaining = resetAt - (now ?? DateTimeOffset.Now);
        if (remaining <= TimeSpan.Zero)
        {
            return "now";
        }

        var totalMinutes = Math.Max((int)remaining.TotalMinutes, 1);
        var days = totalMinutes / 1440;
        var hours = totalMinutes % 1440 / 60;
        var minutes = totalMinutes % 60;

        if (days > 0)
        {
            return hours > 0 ? $"{days}d {hours}h" : $"{days}d";
        }

        if (hours > 0)
        {
            return minutes > 0 ? $"{hours}h {minutes}m" : $"{hours}h";
        }

        return $"{Math.Max(minutes, 1)}m";
    }

    public static string ResetCountdown(
        DateTimeOffset resetAt,
        DateTimeOffset? now = null) =>
        $"resets {((resetAt - (now ?? DateTimeOffset.Now)) <= TimeSpan.Zero ? "now" : $"in {CompactDuration(resetAt, now)}")}";

    public static string RelativeAge(
        DateTimeOffset date,
        DateTimeOffset? now = null)
    {
        var elapsed = (now ?? DateTimeOffset.Now) - date;
        if (elapsed < TimeSpan.FromMinutes(1))
        {
            return "just now";
        }

        var totalMinutes = Math.Max((int)elapsed.TotalMinutes, 1);
        var hours = totalMinutes / 60;
        var minutes = totalMinutes % 60;
        var text = hours > 0
            ? minutes > 0 ? $"{hours}h {minutes}m" : $"{hours}h"
            : $"{minutes}m";
        return $"{text} ago";
    }

    public static string CompactTokenCount(long count)
    {
        var units = new[]
        {
            (Value: 1_000_000_000d, Suffix: "B"),
            (Value: 1_000_000d, Suffix: "M"),
            (Value: 1_000d, Suffix: "K"),
        };

        foreach (var unit in units)
        {
            if (count < unit.Value)
            {
                continue;
            }

            var scaled = count / unit.Value;
            return scaled < 9.95
                ? $"{scaled.ToString("0.0", CultureInfo.InvariantCulture)}{unit.Suffix}"
                : $"{scaled.ToString("0", CultureInfo.InvariantCulture)}{unit.Suffix}";
        }

        return count.ToString(CultureInfo.InvariantCulture);
    }

    public static string TokenCell(
        long value,
        long selectedKindsTotal,
        TokenValueDisplayMode displayMode)
    {
        if (value == 0)
        {
            return "–";
        }

        var valueText = CompactTokenCount(value);
        var percentageText = selectedKindsTotal > 0
            ? $"{((decimal)value / selectedKindsTotal * 100m).ToString("0.#", CultureInfo.InvariantCulture)}%"
            : "–";
        return displayMode switch
        {
            TokenValueDisplayMode.Value => valueText,
            TokenValueDisplayMode.Percentage => percentageText,
            TokenValueDisplayMode.ValueAndPercentage =>
                $"{valueText}\n({percentageText})",
            _ => throw new ArgumentOutOfRangeException(
                nameof(displayMode),
                displayMode,
                null),
        };
    }

    public static string TokenKindShortLabel(TokenKind kind) =>
        kind switch
        {
            TokenKind.DirectInput => "IN",
            TokenKind.Output => "OUT",
            TokenKind.CacheRead => "C·R",
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, null),
        };

    public static string TokenKindSelectionLabel(TokenKindSelection selection)
    {
        if (!selection.IsValid())
        {
            throw new ArgumentOutOfRangeException(
                nameof(selection),
                selection,
                "The selection contains an unknown Token Kind.");
        }

        if (selection == TokenKindSelection.None)
        {
            return "None";
        }

        if (selection == TokenKindSelection.All)
        {
            return "All";
        }

        return string.Join(
            " + ",
            Enum.GetValues<TokenKind>()
                .Where(kind => selection.Includes(kind))
                .Select(TokenKindShortLabel));
    }

    public static string TokenStatusSummary(
        TokenUsage usage,
        TokenRange range,
        TodayMetricMode metric,
        DateOnly? pricingDate = null)
    {
        ArgumentNullException.ThrowIfNull(usage);

        var value = metric switch
        {
            TodayMetricMode.Token =>
                $"T: {CompactTokenCount(usage.BillableTokens)}",
            TodayMetricMode.Usage => $"API: {ApiEquivalentCost(
                ApiPricingCatalog.Estimate(
                    usage,
                    pricingDate))}",
            _ => throw new ArgumentOutOfRangeException(
                nameof(metric),
                metric,
                null),
        };
        return $"{value} · {range.Label()}";
    }

    public static string ApiEquivalentCost(ApiCostEstimate estimate)
    {
        if (!estimate.IsAvailable)
        {
            return "—";
        }

        if (estimate.CostUsd < 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(estimate),
                estimate.CostUsd,
                "API-equivalent cost cannot be negative.");
        }

        var rounded = decimal.Round(
            estimate.CostUsd,
            2,
            MidpointRounding.ToPositiveInfinity);
        var value = rounded.ToString("0.00", CultureInfo.InvariantCulture);
        return $"${value}";
    }

    public static string TokenBreakdown(TokenUsage usage)
    {
        var input = usage.InputTokens + usage.CacheReadTokens;
        return $"input {input:N0} (direct {usage.InputTokens:N0}, " +
               $"cache read {usage.CacheReadTokens:N0}) · output {usage.OutputTokens:N0}";
    }

    private static UsageWindow? SummaryWindow(UsageSnapshot? snapshot) =>
        snapshot?.Windows
            .OrderBy(window =>
                window.Kind == UsageWindowKind.ShortTerm
                    ? 0
                    : window.Kind == UsageWindowKind.Weekly
                        ? 1
                        : 2)
            .ThenBy(window => window.DurationSeconds ?? long.MaxValue)
            .FirstOrDefault();
}
