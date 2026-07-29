using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace TokenStats.Core;

internal enum TranscriptTokenCacheLoadStatus
{
    Miss,
    Loaded,
    Invalid,
}

internal readonly record struct TranscriptTokenCacheLoadResult(
    TranscriptTokenCacheLoadStatus Status,
    TranscriptTokenCacheEntry? Entry);

/// <summary>
/// Best-effort, per-transcript persistence for the incremental JSONL reader.
/// Entries are disposable derived data: cache failures never prevent the
/// transcript itself from being read.
/// </summary>
internal sealed class TranscriptTokenCacheStore
{
    internal const int SchemaVersion = 1;
    internal const int ParserSemanticsVersion = 1;
    internal const long MaximumReadBytes = 64L * 1024 * 1024;

    private const int StreamBufferBytes = 16 * 1024;
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        MaxDepth = 32,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private readonly string cacheDirectory;
    private readonly string timezoneId;

    internal TranscriptTokenCacheStore(
        string cacheDirectory,
        string timezoneId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(cacheDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(timezoneId);

        this.cacheDirectory = Path.GetFullPath(cacheDirectory);
        this.timezoneId = timezoneId;
    }

    internal TranscriptTokenCacheLoadResult Load(string transcriptPath)
    {
        string cachePath;
        string transcriptKey;
        try
        {
            transcriptKey = TranscriptKey(transcriptPath);
            cachePath = CachePath(transcriptKey);
        }
        catch (Exception)
        {
            return Invalid();
        }

        try
        {
            using var stream = new FileStream(
                cachePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete,
                StreamBufferBytes,
                FileOptions.SequentialScan);
            if (stream.Length <= 0 || stream.Length > MaximumReadBytes)
            {
                return Invalid();
            }

            var payload = GC.AllocateUninitializedArray<byte>(
                checked((int)stream.Length));
            var offset = 0;
            while (offset < payload.Length)
            {
                var count = stream.Read(payload, offset, payload.Length - offset);
                if (count == 0)
                {
                    return Invalid();
                }

                offset += count;
            }

            // Enforce the cap even if another process grew a non-atomic cache
            // file after Length was observed.
            if (stream.ReadByte() != -1)
            {
                return Invalid();
            }

            var envelope = JsonSerializer.Deserialize<CacheEnvelope>(
                payload,
                SerializerOptions);
            if (envelope is null ||
                envelope.Schema != SchemaVersion ||
                envelope.ParserSemantics != ParserSemanticsVersion ||
                !string.Equals(
                    envelope.TranscriptKey,
                    transcriptKey,
                    StringComparison.Ordinal) ||
                !string.Equals(
                    envelope.TimezoneId,
                    timezoneId,
                    StringComparison.Ordinal) ||
                envelope.Entry is null ||
                !envelope.Entry.IsValid() ||
                !HasValidChecksum(envelope))
            {
                return Invalid();
            }

            return new TranscriptTokenCacheLoadResult(
                TranscriptTokenCacheLoadStatus.Loaded,
                envelope.Entry);
        }
        catch (FileNotFoundException)
        {
            return Miss();
        }
        catch (DirectoryNotFoundException)
        {
            return Miss();
        }
        catch (Exception)
        {
            return Invalid();
        }
    }

    internal bool Save(
        string transcriptPath,
        TranscriptTokenCacheEntry entry)
    {
        string? temporaryPath = null;
        try
        {
            if (entry is null || !entry.IsValid())
            {
                return false;
            }

            var transcriptKey = TranscriptKey(transcriptPath);
            var cachePath = CachePath(transcriptKey);
            Directory.CreateDirectory(cacheDirectory);
            temporaryPath = Path.Combine(
                cacheDirectory,
                $"{Guid.NewGuid():N}.tmp");
            var envelope = new CacheEnvelope
            {
                Schema = SchemaVersion,
                ParserSemantics = ParserSemanticsVersion,
                TimezoneId = timezoneId,
                TranscriptKey = transcriptKey,
                Entry = entry,
            };
            envelope.Checksum = ComputeChecksum(envelope);

            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       StreamBufferBytes,
                       FileOptions.SequentialScan | FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(
                    stream,
                    envelope,
                    SerializerOptions);
                if (stream.Length > MaximumReadBytes)
                {
                    return false;
                }

                stream.Flush(flushToDisk: true);
            }

            File.Move(temporaryPath, cachePath, overwrite: true);
            temporaryPath = null;
            return true;
        }
        catch (Exception)
        {
            // This is a rebuildable optimization. Parsing the source transcript
            // must remain available when cache persistence fails.
            return false;
        }
        finally
        {
            if (temporaryPath is not null)
            {
                TryDelete(temporaryPath);
            }
        }
    }

    internal void Remove(string transcriptPath)
    {
        try
        {
            File.Delete(CachePath(TranscriptKey(transcriptPath)));
        }
        catch (Exception)
        {
            // Best effort: an invalid entry will be ignored if it remains.
        }
    }

    private static TranscriptTokenCacheLoadResult Miss() => new(
        TranscriptTokenCacheLoadStatus.Miss,
        null);

    private static TranscriptTokenCacheLoadResult Invalid() => new(
        TranscriptTokenCacheLoadStatus.Invalid,
        null);

    private static string TranscriptKey(string transcriptPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(transcriptPath);
        var normalizedPath = Path.TrimEndingDirectorySeparator(
            Path.GetFullPath(transcriptPath));
        if (OperatingSystem.IsWindows())
        {
            normalizedPath = normalizedPath.ToUpperInvariant();
        }

        var digest = SHA256.HashData(
            Encoding.UTF8.GetBytes(normalizedPath));
        return Convert.ToHexString(digest).ToLowerInvariant();
    }

    private string CachePath(string transcriptKey) =>
        Path.Combine(cacheDirectory, $"{transcriptKey}.json");

    private static bool HasValidChecksum(CacheEnvelope envelope)
    {
        if (envelope.Checksum is null ||
            envelope.Checksum.Length != 32)
        {
            return false;
        }

        var expected = ComputeChecksum(envelope);
        try
        {
            return CryptographicOperations.FixedTimeEquals(
                envelope.Checksum,
                expected);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(expected);
        }
    }

    private static byte[] ComputeChecksum(CacheEnvelope envelope)
    {
        var payload = new CacheIntegrityPayload
        {
            Schema = envelope.Schema,
            ParserSemantics = envelope.ParserSemantics,
            TimezoneId = envelope.TimezoneId,
            TranscriptKey = envelope.TranscriptKey,
            Entry = envelope.Entry,
        };
        return SHA256.HashData(
            JsonSerializer.SerializeToUtf8Bytes(
                payload,
                SerializerOptions));
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception)
        {
        }
    }

    private sealed class CacheEnvelope
    {
        public int Schema { get; set; }
        public int ParserSemantics { get; set; }
        public string TimezoneId { get; set; } = string.Empty;
        public string TranscriptKey { get; set; } = string.Empty;
        public TranscriptTokenCacheEntry? Entry { get; set; }
        public byte[] Checksum { get; set; } = [];
    }

    private sealed class CacheIntegrityPayload
    {
        public int Schema { get; set; }
        public int ParserSemantics { get; set; }
        public string TimezoneId { get; set; } = string.Empty;
        public string TranscriptKey { get; set; } = string.Empty;
        public TranscriptTokenCacheEntry? Entry { get; set; }
    }
}

internal sealed class TranscriptTokenCacheEntry
{
    /// <summary>
    /// Offset immediately after the last safely committed complete JSONL line.
    /// </summary>
    public long ConsumedBytes { get; set; }

    public long ObservedLength { get; set; }
    public DateTime LastWriteUtc { get; set; }
    public bool DroppingOversizedLine { get; set; }

    public long PrefixOffset { get; set; }
    public int PrefixLength { get; set; }
    public byte[] PrefixHash { get; set; } = [];

    public long CheckpointOffset { get; set; }
    public int CheckpointLength { get; set; }
    public byte[] CheckpointHash { get; set; } = [];

    public List<string> SeenResponseIds { get; set; } = [];
    public TranscriptTokenUsageSnapshot Usage { get; set; } = new();
    public List<TranscriptDailyUsageSnapshot> PerDay { get; set; } = [];
    public List<TranscriptPendingAgentUsageSnapshot> PendingByAgent { get; set; } = [];
    public List<TranscriptPendingDayUsageSnapshot> PendingByDay { get; set; } = [];
    public string? ActiveCodexModel { get; set; }
    public TranscriptCodexRunningTotalSnapshot? CodexRunningTotal { get; set; }

    internal bool IsValid() =>
        ConsumedBytes >= 0 &&
        ObservedLength >= 0 &&
        ConsumedBytes <= ObservedLength &&
        PrefixOffset >= 0 &&
        PrefixLength >= 0 &&
        CheckpointOffset >= 0 &&
        CheckpointLength >= 0 &&
        PrefixHash is not null &&
        CheckpointHash is not null &&
        SeenResponseIds is not null &&
        SeenResponseIds.Count <= 1_000_000 &&
        !SeenResponseIds.Any(
            static id => id is null || id.Length > 128) &&
        Usage is not null &&
        Usage.IsValid() &&
        PerDay is not null &&
        PerDay.Count <= 100_000 &&
        PerDay.All(static item => item is not null && item.IsValid()) &&
        PendingByAgent is not null &&
        PendingByAgent.Count <= 64 &&
        PendingByAgent.All(static item => item is not null && item.IsValid()) &&
        PendingByDay is not null &&
        PendingByDay.Count <= 100_000 &&
        PendingByDay.All(static item => item is not null && item.IsValid()) &&
        (ActiveCodexModel is null ||
         !string.IsNullOrWhiteSpace(ActiveCodexModel) &&
         ActiveCodexModel.Length <= 1_024) &&
        (CodexRunningTotal is null || CodexRunningTotal.IsValid());
}

internal sealed class TranscriptDailyUsageSnapshot
{
    public DateOnly Day { get; set; }
    public TranscriptTokenUsageSnapshot Usage { get; set; } = new();

    internal bool IsValid() => Usage is not null && Usage.IsValid();
}

internal sealed class TranscriptPendingAgentUsageSnapshot
{
    public AgentId AgentId { get; set; }
    public TranscriptTokenUsageSnapshot Usage { get; set; } = new();

    internal bool IsValid() =>
        Enum.IsDefined(AgentId) &&
        Usage is not null &&
        Usage.IsValid();
}

internal sealed class TranscriptPendingDayUsageSnapshot
{
    public DateOnly Day { get; set; }
    public AgentId AgentId { get; set; }
    public TranscriptTokenUsageSnapshot Usage { get; set; } = new();

    internal bool IsValid() =>
        Enum.IsDefined(AgentId) &&
        Usage is not null &&
        Usage.IsValid();
}

internal sealed class TranscriptTokenUsageSnapshot
{
    public long InputTokens { get; set; }
    public long OutputTokens { get; set; }
    public long CacheWriteTokens { get; set; }
    public long CacheWrite1HourTokens { get; set; }
    public long CacheReadTokens { get; set; }
    public int ResponseCount { get; set; }
    public List<TranscriptModelUsageSnapshot> ModelAttributions { get; set; } = [];

    internal static TranscriptTokenUsageSnapshot FromUsage(TokenUsage usage)
    {
        ArgumentNullException.ThrowIfNull(usage);
        return new TranscriptTokenUsageSnapshot
        {
            InputTokens = usage.InputTokens,
            OutputTokens = usage.OutputTokens,
            CacheWriteTokens = usage.CacheWriteTokens,
            CacheWrite1HourTokens = usage.CacheWrite1HourTokens,
            CacheReadTokens = usage.CacheReadTokens,
            ResponseCount = usage.ResponseCount,
            ModelAttributions = usage.ModelUsage
                .Select(TranscriptModelUsageSnapshot.FromUsage)
                .ToList(),
        };
    }

    internal TokenUsage ToUsage()
    {
        var usage = new TokenUsage
        {
            InputTokens = InputTokens,
            OutputTokens = OutputTokens,
            CacheWriteTokens = CacheWriteTokens,
            CacheWrite1HourTokens = CacheWrite1HourTokens,
            CacheReadTokens = CacheReadTokens,
            ResponseCount = ResponseCount,
        };
        foreach (var attribution in ModelAttributions)
        {
            usage.AddAttribution(
                attribution.AgentId,
                ModelName.FromNullable(attribution.Model),
                attribution.ToUsage());
        }

        return usage;
    }

    internal bool IsValid() =>
        InputTokens >= 0 &&
        OutputTokens >= 0 &&
        CacheWriteTokens >= 0 &&
        CacheWrite1HourTokens >= 0 &&
        CacheReadTokens >= 0 &&
        ResponseCount >= 0 &&
        ModelAttributions is not null &&
        ModelAttributions.Count <= 10_000 &&
        ModelAttributions.All(
            static item => item is not null && item.IsValid());
}

internal sealed class TranscriptModelUsageSnapshot
{
    public AgentId AgentId { get; set; }
    public string? Model { get; set; }
    public long InputTokens { get; set; }
    public long OutputTokens { get; set; }
    public long CacheWriteTokens { get; set; }
    public long CacheWrite1HourTokens { get; set; }
    public long CacheReadTokens { get; set; }
    public int ResponseCount { get; set; }

    internal static TranscriptModelUsageSnapshot FromUsage(
        ModelTokenUsage usage) => new()
    {
        AgentId = usage.AgentId,
        Model = usage.Model,
        InputTokens = usage.Breakdown.RawInputTokens,
        OutputTokens = usage.Breakdown.OutputTokens,
        CacheWriteTokens = usage.Breakdown.CacheWriteTokens,
        CacheWrite1HourTokens = usage.Breakdown.CacheWrite1HourTokens,
        CacheReadTokens = usage.Breakdown.CacheReadTokens,
        ResponseCount = usage.ResponseCount,
    };

    internal TokenUsage ToUsage() => new()
    {
        InputTokens = InputTokens,
        OutputTokens = OutputTokens,
        CacheWriteTokens = CacheWriteTokens,
        CacheWrite1HourTokens = CacheWrite1HourTokens,
        CacheReadTokens = CacheReadTokens,
        ResponseCount = ResponseCount,
    };

    internal bool IsValid() =>
        Enum.IsDefined(AgentId) &&
        (Model is null ||
         !string.IsNullOrWhiteSpace(Model) &&
         Model.Length <= 1_024) &&
        InputTokens >= 0 &&
        OutputTokens >= 0 &&
        CacheWriteTokens >= 0 &&
        CacheWrite1HourTokens >= 0 &&
        CacheReadTokens >= 0 &&
        ResponseCount >= 0;
}

internal sealed class TranscriptCodexRunningTotalSnapshot
{
    public long DirectInput { get; set; }
    public long Output { get; set; }
    public long CacheWrite { get; set; }
    public long CacheWrite1Hour { get; set; }
    public long CacheRead { get; set; }

    internal bool IsValid() =>
        DirectInput >= 0 &&
        Output >= 0 &&
        CacheWrite >= 0 &&
        CacheWrite1Hour >= 0 &&
        CacheRead >= 0;
}
