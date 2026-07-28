using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;

namespace TokenStats.Core;

/// <summary>
/// Incrementally reads Claude Code transcripts and Codex rollout JSONL files.
/// Parse progress is cached per file, so subsequent scans only inspect bytes
/// appended since the previous scan.
/// </summary>
public sealed class TranscriptTokenReader
{
    private const int ReadBufferSize = 64 * 1024;
    private const int MaximumLineBytes = 16 * 1024 * 1024;
    private const int MaximumRetainedPartialBytes = 4 * ReadBufferSize;
    private const int FileIdentityPrefixBytes = 4 * 1024;
    private static readonly TimeSpan StateRetention = TimeSpan.FromHours(48);

    private readonly object sync = new();
    private readonly TimeZoneInfo localTimeZone;
    private readonly Dictionary<string, ParseState> states =
        new(StringComparer.OrdinalIgnoreCase);

    public TranscriptTokenReader(TimeZoneInfo? localTimeZone = null)
    {
        this.localTimeZone = localTimeZone ?? TimeZoneInfo.Local;
    }

    /// <summary>
    /// Returns usage recorded on the local calendar day across every JSONL file
    /// below <paramref name="root"/>, or null when no readable usage exists.
    /// </summary>
    public TokenUsage? TodayUsage(
        string root,
        DateTimeOffset? now = null) =>
        RangeUsage(
            root,
            TokenRange.Today,
            now);

    /// <summary>
    /// Runs the filesystem scan away from the UI thread.
    /// </summary>
    public Task<TokenUsage?> TodayUsageAsync(
        string root,
        DateTimeOffset? now = null,
        CancellationToken cancellationToken = default) =>
        RangeUsageAsync(
            root,
            TokenRange.Today,
            now,
            cancellationToken);

    /// <summary>
    /// Returns usage in a rolling local-calendar range, today inclusive,
    /// grouped by agent and model in <see cref="TokenUsage.ModelUsage"/>.
    /// </summary>
    public TokenUsage? RangeUsage(
        string root,
        TokenRange range,
        DateTimeOffset? now = null) =>
        RangeUsageCore(
            root,
            range,
            now ?? DateTimeOffset.Now,
            CancellationToken.None);

    /// <summary>
    /// Runs a rolling-range filesystem scan away from the UI thread.
    /// </summary>
    public Task<TokenUsage?> RangeUsageAsync(
        string root,
        TokenRange range,
        DateTimeOffset? now = null,
        CancellationToken cancellationToken = default) =>
        Task.Run(
            () => RangeUsageCore(
                root,
                range,
                now ?? DateTimeOffset.Now,
                cancellationToken),
            cancellationToken);

    /// <summary>
    /// Returns all usage in one transcript. Repeated calls only parse appended
    /// bytes; an incomplete trailing JSONL line is retained until completed.
    /// </summary>
    public TokenUsage? UsageForTranscript(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        lock (sync)
        {
            return UsageForTranscriptLocked(
                Path.GetFullPath(path),
                DateTimeOffset.Now,
                CancellationToken.None);
        }
    }

    private TokenUsage? RangeUsageCore(
        string root,
        TokenRange range,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(root);
        lock (sync)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var fullRoot = Path.GetFullPath(root);
            if (!Directory.Exists(fullRoot))
            {
                EvictStaleStates(now);
                return null;
            }

            var rangeStart = range.StartDate(now, localTimeZone);
            var days = Enumerable
                .Range(0, range.Days())
                .Select(rangeStart.AddDays)
                .ToHashSet();
            var combined = new TokenUsage();
            try
            {
                var options = new EnumerationOptions
                {
                    RecurseSubdirectories = true,
                    IgnoreInaccessible = true,
                    ReturnSpecialDirectories = false,
                    AttributesToSkip = FileAttributes.ReparsePoint,
                };

                foreach (var path in Directory.EnumerateFiles(fullRoot, "*", options))
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (!string.Equals(
                            Path.GetExtension(path),
                            ".jsonl",
                            StringComparison.OrdinalIgnoreCase) ||
                        !WasModifiedOnOrAfter(path, rangeStart))
                    {
                        continue;
                    }

                    var fullPath = Path.GetFullPath(path);
                    _ = UsageForTranscriptLocked(
                        fullPath,
                        now,
                        cancellationToken);
                    if (!states.TryGetValue(fullPath, out var state))
                    {
                        continue;
                    }

                    foreach (var day in days)
                    {
                        if (state.PerDay.TryGetValue(day, out var usage))
                        {
                            combined.Add(usage);
                        }
                    }

                    foreach (var item in state.PendingByDay)
                    {
                        if (days.Contains(item.Key.Day))
                        {
                            combined.AddAttribution(
                                item.Key.AgentId,
                                ModelName.Unattributed,
                                item.Value);
                        }
                    }
                }
            }
            catch (DirectoryNotFoundException)
            {
                return null;
            }
            catch (UnauthorizedAccessException)
            {
                return null;
            }
            catch (IOException)
            {
                return null;
            }
            finally
            {
                EvictStaleStates(now);
            }

            return combined.ResponseCount > 0 ? combined : null;
        }
    }

    private bool WasModifiedOnOrAfter(string path, DateOnly day)
    {
        try
        {
            var modifiedUtc = File.GetLastWriteTimeUtc(path);
            var modified = new DateTimeOffset(modifiedUtc, TimeSpan.Zero);
            return LocalDate(modified) >= day;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (IOException)
        {
            return false;
        }
    }

    private TokenUsage? UsageForTranscriptLocked(
        string path,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        FileStream stream;
        try
        {
            stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                ReadBufferSize,
                FileOptions.SequentialScan);
        }
        catch (ArgumentException)
        {
            states.Remove(path);
            return null;
        }
        catch (FileNotFoundException)
        {
            states.Remove(path);
            return null;
        }
        catch (DirectoryNotFoundException)
        {
            states.Remove(path);
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }

        using (stream)
        {
            ParseState state;
            long size;
            try
            {
                size = stream.Length;
                state = states.TryGetValue(path, out var cached)
                    ? cached
                    : new ParseState();
                var lastWriteUtc = File.GetLastWriteTimeUtc(path);
                if (size < state.ConsumedBytes ||
                    (size == state.ConsumedBytes &&
                     state.LastWriteUtc != default &&
                     state.LastWriteUtc != lastWriteUtc) ||
                    !PrefixMatches(stream, state))
                {
                    state = new ParseState();
                }

                CapturePrefix(stream, state, size);
                state.LastWriteUtc = lastWriteUtc;
                state.LastAccessed = now;
                if (size > state.ConsumedBytes)
                {
                    stream.Seek(state.ConsumedBytes, SeekOrigin.Begin);
                    var buffer = new byte[ReadBufferSize];
                    int count;
                    while ((count = stream.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        cancellationToken.ThrowIfCancellationRequested();
                        Ingest(buffer.AsMemory(0, count), state);
                        state.ConsumedBytes += count;
                    }
                }
            }
            catch (IOException)
            {
                return null;
            }

            states[path] = state;
            if (state.Usage.ResponseCount == 0)
            {
                return null;
            }

            var result = state.Usage.Clone();
            foreach (var item in state.PendingByAgent)
            {
                result.AddAttribution(
                    item.Key,
                    ModelName.Unattributed,
                    item.Value);
            }

            return result;
        }
    }

    private void Ingest(ReadOnlyMemory<byte> appended, ParseState state)
    {
        var bytes = appended.Span;
        var lineStart = 0;
        for (var index = 0; index < bytes.Length; index++)
        {
            if (bytes[index] != (byte)'\n')
            {
                continue;
            }

            var segment = appended.Slice(lineStart, index - lineStart);
            if (state.DroppingOversizedLine)
            {
                state.DroppingOversizedLine = false;
                ResetPartialLine(state);
            }
            else if (state.PartialLine.Length == 0)
            {
                if (segment.Length <= MaximumLineBytes)
                {
                    ParseLine(segment, state);
                }
            }
            else if (AppendPartial(segment.Span, state))
            {
                ParseLine(
                    state.PartialLine.GetBuffer().AsMemory(
                        0,
                        checked((int)state.PartialLine.Length)),
                    state);
                ResetPartialLine(state);
            }

            // A newline always ends an oversized line. Do not let one corrupt
            // record suppress the record that follows it.
            state.DroppingOversizedLine = false;
            ResetPartialLine(state);
            lineStart = index + 1;
        }

        if (lineStart < appended.Length && !state.DroppingOversizedLine)
        {
            _ = AppendPartial(appended.Span[lineStart..], state);
        }
    }

    private static bool AppendPartial(
        ReadOnlySpan<byte> segment,
        ParseState state)
    {
        if (state.PartialLine.Length + segment.Length > MaximumLineBytes)
        {
            ResetPartialLine(state);
            state.DroppingOversizedLine = true;
            return false;
        }

        state.PartialLine.Write(segment);
        return true;
    }

    private static bool PrefixMatches(FileStream stream, ParseState state)
    {
        if (state.PrefixHash.Length == 0 || state.PrefixLength == 0)
        {
            return true;
        }

        if (stream.Length < state.PrefixLength)
        {
            return false;
        }

        var current = HashPrefix(stream, state.PrefixLength);
        try
        {
            return CryptographicOperations.FixedTimeEquals(
                current,
                state.PrefixHash);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(current);
        }
    }

    private static void CapturePrefix(
        FileStream stream,
        ParseState state,
        long size)
    {
        if (state.PrefixHash.Length > 0 || size <= 0)
        {
            return;
        }

        state.PrefixLength = checked((int)Math.Min(size, FileIdentityPrefixBytes));
        state.PrefixHash = HashPrefix(stream, state.PrefixLength);
    }

    private static byte[] HashPrefix(FileStream stream, int length)
    {
        var originalPosition = stream.Position;
        var buffer = new byte[length];
        try
        {
            stream.Seek(0, SeekOrigin.Begin);
            var offset = 0;
            while (offset < buffer.Length)
            {
                var count = stream.Read(buffer, offset, buffer.Length - offset);
                if (count == 0)
                {
                    throw new EndOfStreamException(
                        "The transcript changed while its identity was checked.");
                }

                offset += count;
            }

            return SHA256.HashData(buffer);
        }
        finally
        {
            stream.Seek(originalPosition, SeekOrigin.Begin);
            CryptographicOperations.ZeroMemory(buffer);
        }
    }

    private static void ResetPartialLine(ParseState state)
    {
        if (state.PartialLine.Capacity > MaximumRetainedPartialBytes)
        {
            state.PartialLine.Dispose();
            state.PartialLine = new MemoryStream();
            return;
        }

        state.PartialLine.SetLength(0);
    }

    private void ParseLine(ReadOnlyMemory<byte> line, ParseState state)
    {
        if (line.IsEmpty)
        {
            return;
        }

        var bytes = line.Span;
        var carriesUsage =
            bytes.IndexOf("\"usage\""u8) >= 0 ||
            bytes.IndexOf("\"token_count\""u8) >= 0;
        var namesModel =
            !carriesUsage &&
            (bytes.IndexOf("\"turn_context\""u8) >= 0 ||
             bytes.IndexOf("\"thread_settings\""u8) >= 0);
        if (!carriesUsage && !namesModel)
        {
            return;
        }

        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return;
            }

            if (TryReadCodexModel(root, out var codexModel))
            {
                AdoptCodexModel(codexModel, state);
                return;
            }

            if (TryParseClaude(
                    root,
                    state,
                    out var claudeUsage,
                    out var model,
                    out var timestamp))
            {
                Record(
                    AgentId.ClaudeCode,
                    string.IsNullOrWhiteSpace(model)
                        ? null
                        : ModelName.Named(model),
                    claudeUsage,
                    timestamp,
                    state);
                return;
            }

            if (TryParseCodex(
                    root,
                    state,
                    out var codexUsage,
                    out timestamp))
            {
                Record(
                    AgentId.Codex,
                    state.ActiveCodexModel,
                    codexUsage,
                    timestamp,
                    state);
            }
        }
        catch (JsonException)
        {
            // A malformed line is isolated from the remaining append-only file.
        }
    }

    private static bool TryParseClaude(
        JsonElement root,
        ParseState state,
        out TokenUsage usage,
        out string? model,
        out string? timestamp)
    {
        usage = new TokenUsage();
        model = null;
        timestamp = null;
        if (!root.TryGetProperty("message", out var message) ||
            message.ValueKind != JsonValueKind.Object ||
            !message.TryGetProperty("usage", out var rawUsage) ||
            rawUsage.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        if (message.TryGetProperty("id", out var idElement) &&
            idElement.ValueKind == JsonValueKind.String &&
            idElement.GetString() is { } id &&
            !state.SeenResponseIds.Add(id))
        {
            return false;
        }

        usage.InputTokens = Math.Max(ReadInteger(rawUsage, "input_tokens"), 0);
        usage.OutputTokens = Math.Max(ReadInteger(rawUsage, "output_tokens"), 0);
        usage.CacheReadTokens =
            Math.Max(ReadInteger(rawUsage, "cache_read_input_tokens"), 0);

        var aggregateCacheWrite =
            Math.Max(ReadInteger(rawUsage, "cache_creation_input_tokens"), 0);
        usage.CacheWriteTokens = aggregateCacheWrite;
        if (rawUsage.TryGetProperty("cache_creation", out var cacheCreation) &&
            cacheCreation.ValueKind == JsonValueKind.Object)
        {
            var hasFiveMinute = TryReadNonNegativeInteger(
                cacheCreation,
                "ephemeral_5m_input_tokens",
                out var fiveMinute);
            var hasOneHour = TryReadNonNegativeInteger(
                cacheCreation,
                "ephemeral_1h_input_tokens",
                out var oneHour);
            if (hasFiveMinute || hasOneHour)
            {
                var detailedTotal = fiveMinute + oneHour;
                var cacheWriteTotal = aggregateCacheWrite > 0
                    ? aggregateCacheWrite
                    : detailedTotal;
                usage.CacheWrite1HourTokens = Math.Min(oneHour, cacheWriteTotal);
                usage.CacheWriteTokens = Math.Min(
                    fiveMinute,
                    cacheWriteTotal - usage.CacheWrite1HourTokens);
                usage.CacheWriteTokens += Math.Max(
                    cacheWriteTotal -
                    usage.CacheWrite1HourTokens -
                    usage.CacheWriteTokens,
                    0);
            }
        }

        usage.ResponseCount = 1;
        model = ReadString(message, "model");
        timestamp = ReadString(root, "timestamp");
        return true;
    }

    private static bool TryParseCodex(
        JsonElement root,
        ParseState state,
        out TokenUsage usage,
        out string? timestamp)
    {
        usage = new TokenUsage();
        timestamp = null;
        if (!root.TryGetProperty("payload", out var payload) ||
            payload.ValueKind != JsonValueKind.Object ||
            !string.Equals(
                ReadString(payload, "type"),
                "token_count",
                StringComparison.Ordinal) ||
            !payload.TryGetProperty("info", out var info) ||
            info.ValueKind != JsonValueKind.Object ||
            !info.TryGetProperty("total_token_usage", out var rawUsage) ||
            rawUsage.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        var current = ReadCodexRunningTotal(rawUsage);
        var previous = state.CodexRunningTotal ??
                       OpeningBaseline(info, current);
        var directInput = current.DirectInput - previous.DirectInput;
        var output = current.Output - previous.Output;
        var cacheWrite = current.CacheWrite - previous.CacheWrite;
        var cacheWrite1Hour =
            current.CacheWrite1Hour - previous.CacheWrite1Hour;
        var cacheRead = current.CacheRead - previous.CacheRead;

        // A reset or malformed running total contributes nothing, but it still
        // becomes the new baseline. Otherwise every later event would be
        // rejected until the counter climbed back above its former high-water
        // mark.
        if (directInput < 0 ||
            output < 0 ||
            cacheWrite < 0 ||
            cacheWrite1Hour < 0 ||
            cacheRead < 0)
        {
            state.CodexRunningTotal = current;
            return false;
        }

        state.CodexRunningTotal = current;
        usage.InputTokens = directInput;
        usage.OutputTokens = output;
        usage.CacheWriteTokens = cacheWrite;
        usage.CacheWrite1HourTokens = cacheWrite1Hour;
        usage.CacheReadTokens = cacheRead;
        if (usage.OdometerTokens == 0)
        {
            return false;
        }

        usage.ResponseCount = 1;
        timestamp = ReadString(root, "timestamp");
        return true;
    }

    private static CodexRunningTotal ReadCodexRunningTotal(
        JsonElement rawUsage)
    {
        var totalInput = Math.Max(ReadInteger(rawUsage, "input_tokens"), 0);
        var cachedInput = Math.Max(
            ReadInteger(rawUsage, "cached_input_tokens"),
            0);
        var cacheWrite = Math.Max(
            Math.Max(
                ReadInteger(rawUsage, "cache_write_input_tokens"),
                ReadInteger(rawUsage, "cache_write_tokens")),
            0);
        var cacheWrite1Hour = Math.Max(
            Math.Max(
                ReadInteger(rawUsage, "cache_write_1h_input_tokens"),
                ReadInteger(rawUsage, "cache_write_1h_tokens")),
            0);

        if (rawUsage.TryGetProperty("input_tokens_details", out var details) &&
            details.ValueKind == JsonValueKind.Object)
        {
            cachedInput = Math.Max(
                cachedInput,
                Math.Max(
                    ReadInteger(details, "cached_tokens"),
                    ReadInteger(details, "cached_input_tokens")));
            cacheWrite = Math.Max(
                cacheWrite,
                Math.Max(
                    ReadInteger(details, "cache_write_tokens"),
                    ReadInteger(details, "cache_write_input_tokens")));
            cacheWrite1Hour = Math.Max(
                cacheWrite1Hour,
                Math.Max(
                    ReadInteger(details, "cache_write_1h_tokens"),
                    ReadInteger(details, "cache_write_1h_input_tokens")));
        }

        cachedInput = Math.Clamp(cachedInput, 0, totalInput);
        cacheWrite1Hour = Math.Clamp(
            cacheWrite1Hour,
            0,
            totalInput - cachedInput);
        cacheWrite = Math.Clamp(
            cacheWrite,
            0,
            totalInput - cachedInput - cacheWrite1Hour);
        return new CodexRunningTotal(
            totalInput - cachedInput - cacheWrite - cacheWrite1Hour,
            Math.Max(ReadInteger(rawUsage, "output_tokens"), 0),
            cacheWrite,
            cacheWrite1Hour,
            cachedInput);
    }

    private static CodexRunningTotal OpeningBaseline(
        JsonElement info,
        CodexRunningTotal current)
    {
        if (!info.TryGetProperty("last_token_usage", out var lastUsage) ||
            lastUsage.ValueKind != JsonValueKind.Object)
        {
            return default;
        }

        var turn = ReadCodexRunningTotal(lastUsage);
        if (turn == default)
        {
            return default;
        }

        return current.Subtracting(turn);
    }

    private static bool TryReadCodexModel(
        JsonElement root,
        out ModelName model)
    {
        model = ModelName.Unattributed;
        if (!root.TryGetProperty("payload", out var payload) ||
            payload.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        string? value = null;
        if (string.Equals(
                ReadString(root, "type"),
                "turn_context",
                StringComparison.Ordinal))
        {
            value = ReadString(payload, "model");
        }
        else if (string.Equals(
                     ReadString(payload, "type"),
                     "thread_settings_applied",
                     StringComparison.Ordinal) &&
                 payload.TryGetProperty(
                     "thread_settings",
                     out var threadSettings) &&
                 threadSettings.ValueKind == JsonValueKind.Object)
        {
            value = ReadString(threadSettings, "model");
        }

        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        model = ModelName.Named(value);
        return true;
    }

    private static void AdoptCodexModel(
        ModelName model,
        ParseState state)
    {
        state.ActiveCodexModel = model;
        if (state.PendingByAgent.Remove(
                AgentId.Codex,
                out var allPending))
        {
            state.Usage.AddAttribution(
                AgentId.Codex,
                model,
                allPending);
        }

        foreach (var item in state.PendingByDay
                     .Where(item => item.Key.AgentId == AgentId.Codex)
                     .ToArray())
        {
            if (state.PerDay.TryGetValue(item.Key.Day, out var daily))
            {
                daily.AddAttribution(
                    AgentId.Codex,
                    model,
                    item.Value);
            }

            state.PendingByDay.Remove(item.Key);
        }
    }

    private void Record(
        AgentId agentId,
        ModelName? model,
        TokenUsage usage,
        string? timestamp,
        ParseState state)
    {
        // Claude can write synthetic all-zero responses, and duplicate Codex
        // running totals produce zero deltas. Neither is a response or a row.
        if (usage.OdometerTokens == 0)
        {
            return;
        }

        state.Usage.Add(usage);
        if (model is { } attributedModel)
        {
            state.Usage.AddAttribution(
                agentId,
                attributedModel,
                usage);
        }
        else
        {
            if (!state.PendingByAgent.TryGetValue(
                    agentId,
                    out var pending))
            {
                pending = new TokenUsage();
                state.PendingByAgent.Add(agentId, pending);
            }

            pending.Add(usage);
        }

        if (!TryParseTimestamp(timestamp, out var parsed))
        {
            return;
        }

        var day = LocalDate(parsed);
        if (!state.PerDay.TryGetValue(day, out var daily))
        {
            daily = new TokenUsage();
            state.PerDay.Add(day, daily);
        }

        daily.Add(usage);
        if (model is { } dailyModel)
        {
            daily.AddAttribution(agentId, dailyModel, usage);
            return;
        }

        var pendingKey = new PendingUsageKey(day, agentId);
        if (!state.PendingByDay.TryGetValue(
                pendingKey,
                out var dailyPending))
        {
            dailyPending = new TokenUsage();
            state.PendingByDay.Add(pendingKey, dailyPending);
        }

        dailyPending.Add(usage);
    }

    private static long ReadInteger(JsonElement element, string property)
    {
        if (!element.TryGetProperty(property, out var raw) ||
            raw.ValueKind != JsonValueKind.Number)
        {
            return 0;
        }

        if (raw.TryGetInt64(out var integer))
        {
            return integer;
        }

        return raw.TryGetDouble(out var number)
            ? (long)number
            : 0;
    }

    private static bool TryReadNonNegativeInteger(
        JsonElement element,
        string property,
        out long value)
    {
        value = 0;
        if (!element.TryGetProperty(property, out var raw) ||
            raw.ValueKind != JsonValueKind.Number)
        {
            return false;
        }

        value = Math.Max(ReadInteger(element, property), 0);
        return true;
    }

    private static string? ReadString(JsonElement element, string property) =>
        element.TryGetProperty(property, out var raw) &&
        raw.ValueKind == JsonValueKind.String
            ? raw.GetString()
            : null;

    private static bool TryParseTimestamp(
        string? value,
        out DateTimeOffset timestamp) =>
        DateTimeOffset.TryParse(
            value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AllowWhiteSpaces |
            DateTimeStyles.AssumeUniversal |
            DateTimeStyles.AdjustToUniversal,
            out timestamp);

    private DateOnly LocalDate(DateTimeOffset timestamp) =>
        DateOnly.FromDateTime(
            TimeZoneInfo.ConvertTime(timestamp, localTimeZone).DateTime);

    private void EvictStaleStates(DateTimeOffset now)
    {
        var cutoff = now - StateRetention;
        foreach (var path in states
                     .Where(item => item.Value.LastAccessed < cutoff)
                     .Select(item => item.Key)
                     .ToArray())
        {
            states.Remove(path);
        }
    }

    private sealed class ParseState
    {
        public long ConsumedBytes { get; set; }
        public MemoryStream PartialLine { get; set; } = new();
        public bool DroppingOversizedLine { get; set; }
        public int PrefixLength { get; set; }
        public byte[] PrefixHash { get; set; } = [];
        public HashSet<string> SeenResponseIds { get; } =
            new(StringComparer.Ordinal);
        public TokenUsage Usage { get; } = new();
        public Dictionary<DateOnly, TokenUsage> PerDay { get; } = [];
        public Dictionary<AgentId, TokenUsage> PendingByAgent { get; } = [];
        public Dictionary<PendingUsageKey, TokenUsage> PendingByDay { get; } = [];
        public ModelName? ActiveCodexModel { get; set; }
        public CodexRunningTotal? CodexRunningTotal { get; set; }
        public DateTimeOffset LastAccessed { get; set; } = DateTimeOffset.Now;
        public DateTime LastWriteUtc { get; set; }
    }

    private readonly record struct PendingUsageKey(
        DateOnly Day,
        AgentId AgentId);

    private readonly record struct CodexRunningTotal(
        long DirectInput,
        long Output,
        long CacheWrite,
        long CacheWrite1Hour,
        long CacheRead)
    {
        public CodexRunningTotal Subtracting(CodexRunningTotal other) => new(
            Math.Max(DirectInput - other.DirectInput, 0),
            Math.Max(Output - other.Output, 0),
            Math.Max(CacheWrite - other.CacheWrite, 0),
            Math.Max(CacheWrite1Hour - other.CacheWrite1Hour, 0),
            Math.Max(CacheRead - other.CacheRead, 0));
    }
}
