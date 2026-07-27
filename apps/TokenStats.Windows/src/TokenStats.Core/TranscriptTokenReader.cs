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
        TodayUsageCore(root, now ?? DateTimeOffset.Now, CancellationToken.None);

    /// <summary>
    /// Runs the filesystem scan away from the UI thread.
    /// </summary>
    public Task<TokenUsage?> TodayUsageAsync(
        string root,
        DateTimeOffset? now = null,
        CancellationToken cancellationToken = default) =>
        Task.Run(
            () => TodayUsageCore(
                root,
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

    private TokenUsage? TodayUsageCore(
        string root,
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

            var today = LocalDate(now);
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
                        !WasModifiedOnOrAfter(path, today))
                    {
                        continue;
                    }

                    var fullPath = Path.GetFullPath(path);
                    _ = UsageForTranscriptLocked(
                        fullPath,
                        now,
                        cancellationToken);
                    if (states.TryGetValue(fullPath, out var state) &&
                        state.PerDay.TryGetValue(today, out var usage))
                    {
                        combined.Add(usage);
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
            return state.Usage.ResponseCount > 0
                ? state.Usage.Clone()
                : null;
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
        if (bytes.IndexOf("\"usage\""u8) < 0 &&
            bytes.IndexOf("\"token_count\""u8) < 0 &&
            bytes.IndexOf("\"turn_context\""u8) < 0)
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

            if (TryUpdateCodexModel(root, state))
            {
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
                    model,
                    claudeUsage,
                    timestamp,
                    state);
                return;
            }

            if (TryParseCodex(root, out var codexUsage, out timestamp))
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
            !info.TryGetProperty("last_token_usage", out var rawUsage) ||
            rawUsage.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        var totalInput = Math.Max(ReadInteger(rawUsage, "input_tokens"), 0);
        var cachedInput = Math.Max(
            ReadInteger(rawUsage, "cached_input_tokens"),
            0);
        var cacheWrite = Math.Max(
            ReadInteger(rawUsage, "cache_write_input_tokens"),
            ReadInteger(rawUsage, "cache_write_tokens"));
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
        }

        cachedInput = Math.Clamp(cachedInput, 0, totalInput);
        cacheWrite = Math.Clamp(cacheWrite, 0, totalInput - cachedInput);
        usage.InputTokens = totalInput - cachedInput - cacheWrite;
        usage.OutputTokens = Math.Max(ReadInteger(rawUsage, "output_tokens"), 0);
        usage.CacheWriteTokens = cacheWrite;
        usage.CacheReadTokens = cachedInput;
        usage.ResponseCount = 1;
        timestamp = ReadString(root, "timestamp");
        return true;
    }

    private static bool TryUpdateCodexModel(
        JsonElement root,
        ParseState state)
    {
        if (!string.Equals(
                ReadString(root, "type"),
                "turn_context",
                StringComparison.Ordinal) ||
            !root.TryGetProperty("payload", out var payload) ||
            payload.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        state.ActiveCodexModel = ReadString(payload, "model");
        return true;
    }

    private void Record(
        AgentId agentId,
        string? model,
        TokenUsage usage,
        string? timestamp,
        ParseState state)
    {
        state.Usage.AddAttributed(agentId, model, usage);
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

        daily.AddAttributed(agentId, model, usage);
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
        public string? ActiveCodexModel { get; set; }
        public DateTimeOffset LastAccessed { get; set; } = DateTimeOffset.Now;
        public DateTime LastWriteUtc { get; set; }
    }
}
