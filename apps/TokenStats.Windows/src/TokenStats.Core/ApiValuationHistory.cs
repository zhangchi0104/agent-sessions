using System.Globalization;
using System.Text.Json;

namespace TokenStats.Core;

/// <summary>
/// Durable audit output for the last API-equivalent calculation made under a
/// catalog revision. It never replaces transcript truth or the live estimate.
/// </summary>
public sealed record ApiValuationSnapshot(
    int SchemaVersion,
    string ScopeKey,
    string CatalogRevision,
    TokenRange Range,
    DateOnly FirstUsageDay,
    DateOnly LastUsageDay,
    DateTimeOffset CalculatedAt,
    string ExactCostUsd,
    long PricedTokens,
    long UnpricedTokens,
    long DirectInputTokens,
    long OutputTokens,
    long CacheReadTokens,
    IReadOnlyList<string> PriceObservationIds)
{
    public const int CurrentSchemaVersion = 1;
    private const string CanonicalDecimalFormat =
        "0.############################";

    public string StorageKey => $"{ScopeKey}|{CatalogRevision}";

    public bool HasSameCalculation(ApiValuationSnapshot other) =>
        StorageKey == other.StorageKey &&
        Range == other.Range &&
        FirstUsageDay == other.FirstUsageDay &&
        LastUsageDay == other.LastUsageDay &&
        ExactCostUsd == other.ExactCostUsd &&
        PricedTokens == other.PricedTokens &&
        UnpricedTokens == other.UnpricedTokens &&
        DirectInputTokens == other.DirectInputTokens &&
        OutputTokens == other.OutputTokens &&
        CacheReadTokens == other.CacheReadTokens &&
        PriceObservationIds.SequenceEqual(other.PriceObservationIds);

    public bool IsValid =>
        SchemaVersion == CurrentSchemaVersion &&
        !string.IsNullOrWhiteSpace(ScopeKey) &&
        !string.IsNullOrWhiteSpace(CatalogRevision) &&
        Enum.IsDefined(Range) &&
        FirstUsageDay <= LastUsageDay &&
        decimal.TryParse(
            ExactCostUsd,
            NumberStyles.Number,
            CultureInfo.InvariantCulture,
            out _) &&
        PricedTokens >= 0 &&
        UnpricedTokens >= 0 &&
        DirectInputTokens >= 0 &&
        OutputTokens >= 0 &&
        CacheReadTokens >= 0 &&
        PriceObservationIds is not null &&
        PriceObservationIds.SequenceEqual(
            PriceObservationIds
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal));

    public static ApiValuationSnapshot Create(
        TokenUsage usage,
        TokenRange range,
        ApiCostEstimate estimate,
        DateTimeOffset calculatedAt,
        TimeZoneInfo? localTimeZone = null)
    {
        ArgumentNullException.ThrowIfNull(usage);
        ArgumentNullException.ThrowIfNull(estimate);
        var timeZone = localTimeZone ?? TimeZoneInfo.Local;
        var fallbackDay = DateOnly.FromDateTime(
            TimeZoneInfo.ConvertTime(calculatedAt, timeZone).DateTime);
        var dated = usage.DatedModelUsage;
        var firstDay = dated.Count > 0
            ? dated.Min(item => item.Day)
            : fallbackDay;
        var lastDay = dated.Count > 0
            ? dated.Max(item => item.Day)
            : fallbackDay;
        var modelRows = dated.Count > 0
            ? dated.Select(item => (
                item.AgentId,
                item.Model,
                PricingDay: item.Day))
            : usage.ModelUsage.Select(item => (
                item.AgentId,
                item.Model,
                PricingDay: fallbackDay));
        var observationIds = modelRows
            .Where(item => item.Model is not null)
            .Select(item => ApiPricingCatalog.TryResolveObservation(
                item.AgentId,
                item.Model!,
                item.PricingDay,
                out var observation)
                    ? observation.Id
                    : null)
            .Where(id => id is not null)
            .Select(id => id!)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();
        var agentScope = usage.ModelUsage
            .Select(item => item.AgentId.ToString())
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();

        return new ApiValuationSnapshot(
            CurrentSchemaVersion,
            $"{range}|{string.Join(',', agentScope)}",
            ApiPricingCatalog.Revision,
            range,
            firstDay,
            lastDay,
            calculatedAt,
            // Decimal arithmetic preserves operand scale, so numerically equal
            // estimates can otherwise persist as either "9" or "9.00". Keep
            // the audit key canonical without allowing scientific notation,
            // which `IsValid` deliberately rejects.
            estimate.CostUsd.ToString(
                CanonicalDecimalFormat,
                CultureInfo.InvariantCulture),
            estimate.PricedTokens,
            estimate.UnpricedTokens,
            usage.InputTokens,
            usage.OutputTokens,
            usage.CacheReadTokens,
            observationIds);
    }
}

/// <summary>
/// Versioned JSON persistence. One row per scope and catalog revision is
/// replaced as today's usage grows; older catalog revisions remain immutable.
/// </summary>
public sealed class ApiValuationHistoryStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private readonly object gate = new();

    public ApiValuationHistoryStore(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        Path = System.IO.Path.GetFullPath(path);
    }

    public string Path { get; }

    public IReadOnlyList<ApiValuationSnapshot> Load()
    {
        lock (gate)
        {
            return TryLoadCore(out var snapshots) ? snapshots : [];
        }
    }

    /// <summary>
    /// Best-effort audit persistence. An unreadable or unsupported existing
    /// history is never treated as an empty one, because doing so would erase
    /// the very catalog revisions this store exists to preserve.
    /// </summary>
    public bool TrySave(ApiValuationSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (!snapshot.IsValid)
        {
            return false;
        }

        try
        {
            lock (gate)
            {
                if (!TryLoadCore(out var loaded))
                {
                    return false;
                }

                var byKey = loaded.ToDictionary(item => item.StorageKey);
                if (byKey.TryGetValue(snapshot.StorageKey, out var existing) &&
                    existing.HasSameCalculation(snapshot))
                {
                    return true;
                }
                byKey[snapshot.StorageKey] = snapshot;
                WriteCore(byKey.Values
                    .OrderBy(item => item.CalculatedAt)
                    .ThenBy(item => item.StorageKey, StringComparer.Ordinal)
                    .ToArray());
                return true;
            }
        }
        catch (Exception exception) when (
            exception is IOException or
                UnauthorizedAccessException or
                System.Security.SecurityException)
        {
            return false;
        }
    }

    private bool TryLoadCore(
        out IReadOnlyList<ApiValuationSnapshot> snapshots)
    {
        if (!File.Exists(Path))
        {
            snapshots = [];
            return true;
        }

        try
        {
            using var stream = File.OpenRead(Path);
            var decoded = JsonSerializer.Deserialize<ApiValuationSnapshot[]>(
                stream,
                JsonOptions);
            if (decoded is null ||
                decoded.Any(item => item is null || !item.IsValid) ||
                decoded.Select(item => item.StorageKey).Distinct().Count() !=
                    decoded.Length)
            {
                snapshots = [];
                return false;
            }

            snapshots = decoded;
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or
                UnauthorizedAccessException or
                JsonException or
                System.Security.SecurityException)
        {
            snapshots = [];
            return false;
        }
    }

    private void WriteCore(IReadOnlyList<ApiValuationSnapshot> snapshots)
    {
        var directory = System.IO.Path.GetDirectoryName(Path);
        if (string.IsNullOrWhiteSpace(directory))
        {
            throw new InvalidOperationException(
                $"Valuation history path has no parent directory: {Path}");
        }

        Directory.CreateDirectory(directory);
        var temporaryPath = System.IO.Path.Combine(
            directory,
            $".{System.IO.Path.GetFileName(Path)}.{Environment.ProcessId}." +
            $"{Guid.NewGuid():N}.tmp");
        var payload = JsonSerializer.SerializeToUtf8Bytes(snapshots, JsonOptions);
        try
        {
            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       16 * 1024,
                       FileOptions.WriteThrough))
            {
                stream.Write(payload);
                stream.Flush(flushToDisk: true);
            }

            if (File.Exists(Path))
            {
                try
                {
                    File.Replace(temporaryPath, Path, null);
                }
                catch (PlatformNotSupportedException)
                {
                    File.Move(temporaryPath, Path, overwrite: true);
                }
            }
            else
            {
                File.Move(temporaryPath, Path);
            }
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }
}
