using System.Globalization;
using System.Text.Json;

namespace TokenStats.Core;

public static class ClaudeUsageParser
{
    public static IReadOnlyList<UsageWindow> Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var windows = new List<UsageWindow>();

        AddWindow(
            root,
            "five_hour",
            "5-hour",
            UsageWindowKind.ShortTerm,
            18_000,
            windows);
        AddWindow(
            root,
            "seven_day",
            "Weekly",
            UsageWindowKind.Weekly,
            604_800,
            windows);
        AddFableWindow(root, windows);
        return windows;
    }

    private static void AddWindow(
        JsonElement root,
        string property,
        string label,
        UsageWindowKind kind,
        long durationSeconds,
        ICollection<UsageWindow> windows)
    {
        if (!root.TryGetProperty(property, out var raw) ||
            raw.ValueKind != JsonValueKind.Object ||
            !TryGetFiniteDouble(raw, "utilization", out var percent) ||
            !raw.TryGetProperty("resets_at", out var reset))
        {
            return;
        }

        if (!TryParseReset(reset, out var resetAt))
        {
            return;
        }

        windows.Add(new UsageWindow(
            label,
            percent,
            resetAt,
            kind,
            durationSeconds));
    }

    private static void AddFableWindow(
        JsonElement root,
        ICollection<UsageWindow> windows)
    {
        if (!root.TryGetProperty("limits", out var limits) ||
            limits.ValueKind != JsonValueKind.Array)
        {
            return;
        }

        foreach (var limit in limits.EnumerateArray())
        {
            if (limit.ValueKind != JsonValueKind.Object ||
                !TryGetString(limit, "kind", out var kind) ||
                !string.Equals(kind, "weekly_scoped", StringComparison.Ordinal) ||
                !TryGetModelName(limit, out var modelName) ||
                !modelName.Contains("fable", StringComparison.OrdinalIgnoreCase) ||
                !TryGetFiniteDouble(limit, "percent", out var percent))
            {
                continue;
            }

            DateTimeOffset? resetAt = null;
            if (limit.TryGetProperty("resets_at", out var reset) &&
                !TryParseReset(reset, out resetAt))
            {
                continue;
            }

            windows.Add(new UsageWindow(
                "Fable",
                percent,
                resetAt,
                UsageWindowKind.Weekly,
                604_800));
            return;
        }
    }

    private static bool TryGetModelName(JsonElement limit, out string modelName)
    {
        modelName = string.Empty;
        return limit.TryGetProperty("scope", out var scope) &&
               scope.ValueKind == JsonValueKind.Object &&
               scope.TryGetProperty("model", out var model) &&
               model.ValueKind == JsonValueKind.Object &&
               TryGetString(model, "display_name", out modelName);
    }

    private static bool TryGetString(
        JsonElement element,
        string property,
        out string value)
    {
        value = string.Empty;
        return element.TryGetProperty(property, out var raw) &&
               raw.ValueKind == JsonValueKind.String &&
               (value = raw.GetString() ?? string.Empty).Length > 0;
    }

    private static bool TryGetFiniteDouble(
        JsonElement element,
        string property,
        out double value)
    {
        value = 0;
        return element.TryGetProperty(property, out var raw) &&
               raw.ValueKind == JsonValueKind.Number &&
               raw.TryGetDouble(out value) &&
               double.IsFinite(value);
    }

    private static bool TryParseReset(
        JsonElement reset,
        out DateTimeOffset? resetAt)
    {
        resetAt = null;
        if (reset.ValueKind == JsonValueKind.Null)
        {
            return true;
        }

        if (reset.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        if (!DateTimeOffset.TryParse(
                reset.GetString(),
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind,
                out var parsed))
        {
            return false;
        }

        resetAt = parsed;
        return true;
    }
}

public static class CodexUsageParser
{
    public static IReadOnlyList<UsageWindow> Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var windows = new List<UsageWindow>();

        if (!root.TryGetProperty("rate_limit", out var rateLimit) ||
            rateLimit.ValueKind != JsonValueKind.Object)
        {
            return windows;
        }

        AddWindow(
            rateLimit,
            "primary_window",
            "5-hour",
            UsageWindowKind.ShortTerm,
            windows);
        AddWindow(
            rateLimit,
            "secondary_window",
            "Weekly",
            UsageWindowKind.Weekly,
            windows);
        return windows;
    }

    public static bool IsRecognizedNoLimit(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            if (!root.TryGetProperty("rate_limit", out var rateLimit))
            {
                return root.TryGetProperty("credits", out _) ||
                       root.TryGetProperty("agentic_usage", out _);
            }

            if (rateLimit.ValueKind == JsonValueKind.Null)
            {
                return true;
            }

            return rateLimit.ValueKind == JsonValueKind.Object &&
                   IsMissingOrNull(rateLimit, "primary_window") &&
                   IsMissingOrNull(rateLimit, "secondary_window");
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static void AddWindow(
        JsonElement root,
        string property,
        string fallbackLabel,
        UsageWindowKind fallbackKind,
        ICollection<UsageWindow> windows)
    {
        if (!root.TryGetProperty(property, out var raw) ||
            raw.ValueKind != JsonValueKind.Object ||
            !TryGetFiniteDouble(raw, "used_percent", out var percent))
        {
            return;
        }

        var resetProperty = raw.TryGetProperty("reset_at", out _)
            ? "reset_at"
            : "resets_at";
        if (!TryParseEpochReset(raw, resetProperty, out var resetAt))
        {
            return;
        }

        var duration =
            ReadPositiveInteger(raw, "limit_window_seconds") ??
            ReadPositiveInteger(raw, "window_seconds");
        if (duration is null &&
            ReadPositiveInteger(raw, "window_minutes") is { } minutes &&
            minutes <= long.MaxValue / 60)
        {
            duration = minutes * 60;
        }
        var (label, kind) = duration is { } seconds
            ? DescribeWindow(seconds)
            : (fallbackLabel, fallbackKind);
        windows.Add(new UsageWindow(label, percent, resetAt, kind, duration));
    }

    private static (string Label, UsageWindowKind Kind) DescribeWindow(
        long durationSeconds)
    {
        if (durationSeconds == 604_800)
        {
            return ("Weekly", UsageWindowKind.Weekly);
        }

        if (durationSeconds % 86_400 == 0)
        {
            return (
                $"{durationSeconds / 86_400}-day",
                UsageWindowKind.Unknown);
        }

        if (durationSeconds % 3_600 == 0)
        {
            return (
                $"{durationSeconds / 3_600}-hour",
                UsageWindowKind.ShortTerm);
        }

        if (durationSeconds % 60 == 0)
        {
            return (
                $"{durationSeconds / 60}-minute",
                UsageWindowKind.ShortTerm);
        }

        return ($"{durationSeconds}-second", UsageWindowKind.Unknown);
    }

    private static bool TryGetFiniteDouble(
        JsonElement element,
        string property,
        out double value)
    {
        value = 0;
        return element.TryGetProperty(property, out var raw) &&
               raw.ValueKind == JsonValueKind.Number &&
               raw.TryGetDouble(out value) &&
               double.IsFinite(value);
    }

    private static long? ReadPositiveInteger(
        JsonElement element,
        string property)
    {
        if (!element.TryGetProperty(property, out var raw) ||
            raw.ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        if (raw.TryGetInt64(out var integer) && integer > 0)
        {
            return integer;
        }

        if (raw.TryGetDouble(out var number) &&
            double.IsFinite(number) &&
            number > 0 &&
            number <= long.MaxValue)
        {
            return (long)number;
        }

        return null;
    }

    private static bool TryParseEpochReset(
        JsonElement element,
        string property,
        out DateTimeOffset? resetAt)
    {
        resetAt = null;
        if (!element.TryGetProperty(property, out var reset) ||
            reset.ValueKind == JsonValueKind.Null)
        {
            return true;
        }

        if (reset.ValueKind != JsonValueKind.Number ||
            !reset.TryGetDouble(out var epochSeconds) ||
            !double.IsFinite(epochSeconds))
        {
            return false;
        }

        if (epochSeconds <= 0)
        {
            return true;
        }

        try
        {
            resetAt = DateTimeOffset.FromUnixTimeSeconds((long)epochSeconds);
            return true;
        }
        catch (ArgumentOutOfRangeException)
        {
            return false;
        }
    }

    private static bool IsMissingOrNull(
        JsonElement element,
        string property) =>
        !element.TryGetProperty(property, out var raw) ||
        raw.ValueKind == JsonValueKind.Null;
}

public static class CursorUsageParser
{
    public static IReadOnlyList<UsageWindow> Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.TryGetProperty("enabled", out var enabled) &&
            enabled.ValueKind == JsonValueKind.False)
        {
            return [];
        }

        if (!TryGetProperty(root, "planUsage", "plan_usage", out var plan) ||
            plan.ValueKind != JsonValueKind.Object)
        {
            return [];
        }

        DateTimeOffset? resetAt = null;
        if (TryGetFiniteDouble(
                root,
                "billingCycleEnd",
                "billing_cycle_end",
                out var milliseconds) &&
            milliseconds > 0 &&
            milliseconds <= long.MaxValue)
        {
            try
            {
                resetAt = DateTimeOffset.FromUnixTimeMilliseconds(
                    (long)Math.Truncate(milliseconds));
            }
            catch (ArgumentOutOfRangeException)
            {
                resetAt = null;
            }
        }

        if (!TryGetFiniteDouble(
                plan,
                "autoPercentUsed",
                "auto_percent_used",
                out var cursorModelsPercent) ||
            !TryGetFiniteDouble(
                plan,
                "apiPercentUsed",
                "api_percent_used",
                out var otherModelsPercent))
        {
            return [];
        }

        return
        [
            new UsageWindow(
                "Cursor Models",
                Math.Clamp(cursorModelsPercent, 0, 100),
                resetAt),
            new UsageWindow(
                "Other Models",
                Math.Clamp(otherModelsPercent, 0, 100),
                resetAt),
        ];
    }

    private static bool TryGetFiniteDouble(
        JsonElement element,
        string camelCase,
        string snakeCase,
        out double value)
    {
        value = 0;
        if (!TryGetProperty(element, camelCase, snakeCase, out var raw))
        {
            return false;
        }

        var decoded = raw.ValueKind switch
        {
            JsonValueKind.Number => raw.TryGetDouble(out value),
            JsonValueKind.String => double.TryParse(
                raw.GetString(),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out value),
            _ => false,
        };
        return decoded && double.IsFinite(value);
    }

    private static bool TryGetProperty(
        JsonElement element,
        string camelCase,
        string snakeCase,
        out JsonElement value) =>
        element.TryGetProperty(camelCase, out value) ||
        element.TryGetProperty(snakeCase, out value);
}
