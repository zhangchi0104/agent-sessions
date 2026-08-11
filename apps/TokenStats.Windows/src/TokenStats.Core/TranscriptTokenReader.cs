using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace TokenStats.Core;

public readonly record struct TranscriptReadStatistics(
    long CacheLoads,
    long CacheMisses,
    long CacheInvalidations,
    long CacheWrites,
    long ContentBytesRead,
    long TargetedRefreshes);

/// <summary>
/// Incrementally reads Claude Code transcripts and Codex rollout JSONL files.
/// Parse progress is cached per file in memory and can be checkpointed to an
/// app-private cache directory, so subsequent scans only parse appended bytes.
/// </summary>
public sealed class TranscriptTokenReader
{
    private const int ReadBufferSize = 64 * 1024;
    private const int MaximumLineBytes = 16 * 1024 * 1024;
    private const int MaximumRetainedPartialBytes = 4 * ReadBufferSize;
    private const int FileIdentityPrefixBytes = 4 * 1024;
    private const int FileIdentityCheckpointBytes = 4 * 1024;
    private static readonly TimeSpan StateRetention = TimeSpan.FromHours(48);

    private readonly object sync = new();
    private readonly TimeZoneInfo localTimeZone;
    private readonly TranscriptTokenCacheStore? cacheStore;
    private readonly Dictionary<string, ParseState> states =
        new(StringComparer.OrdinalIgnoreCase);
    private long cacheLoads;
    private long cacheMisses;
    private long cacheInvalidations;
    private long cacheWrites;
    private long contentBytesRead;
    private long targetedRefreshes;

    public TranscriptTokenReader(
        TimeZoneInfo? localTimeZone = null,
        string? cacheDirectory = null)
    {
        this.localTimeZone = localTimeZone ?? TimeZoneInfo.Local;
        cacheStore = string.IsNullOrWhiteSpace(cacheDirectory)
            ? null
            : new TranscriptTokenCacheStore(
                cacheDirectory,
                this.localTimeZone.Id);
    }

    public TranscriptReadStatistics Statistics
    {
        get
        {
            lock (sync)
            {
                return new TranscriptReadStatistics(
                    cacheLoads,
                    cacheMisses,
                    cacheInvalidations,
                    cacheWrites,
                    contentBytesRead,
                    targetedRefreshes);
            }
        }
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
            CancellationToken.None,
            changedPaths: null);

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
                cancellationToken,
                changedPaths: null),
            cancellationToken);

    /// <summary>
    /// Reconciles only transcript paths reported by the filesystem watcher,
    /// then recomputes the selected range from the in-memory/cache index.
    /// Manual refreshes and range changes should still use
    /// <see cref="RangeUsageAsync"/> for a full directory reconciliation.
    /// </summary>
    public Task<TokenUsage?> RefreshRangeAsync(
        string root,
        TokenRange range,
        IReadOnlyCollection<string> changedPaths,
        DateTimeOffset? now = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(changedPaths);
        return Task.Run(
            () => RangeUsageCore(
                root,
                range,
                now ?? DateTimeOffset.Now,
                cancellationToken,
                changedPaths),
            cancellationToken);
    }

    /// <summary>
    /// Returns all usage in one transcript. Repeated calls only parse appended
    /// bytes; an incomplete trailing JSONL line is retained until completed.
    /// </summary>
    public TokenUsage? UsageForTranscript(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        lock (sync)
        {
            var fullPath = Path.GetFullPath(path);
            if (states.TryGetValue(fullPath, out var state))
            {
                state.RequiresIdentityValidation = true;
            }

            return UsageForTranscriptLocked(
                fullPath,
                DateTimeOffset.Now,
                CancellationToken.None);
        }
    }

    private TokenUsage? RangeUsageCore(
        string root,
        TokenRange range,
        DateTimeOffset now,
        CancellationToken cancellationToken,
        IReadOnlyCollection<string>? changedPaths)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(root);
        lock (sync)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var fullRoot = Path.GetFullPath(root);
            if (!Directory.Exists(fullRoot))
            {
                foreach (var path in states.Keys
                             .Where(path => IsPathBelowRoot(fullRoot, path))
                             .ToArray())
                {
                    RemoveState(path, removePersistentCache: true);
                }

                EvictStaleStates(now);
                return null;
            }

            var rangeStart = range.StartDate(now, localTimeZone);
            var days = Enumerable
                .Range(0, range.Days())
                .Select(rangeStart.AddDays)
                .ToHashSet();
            HashSet<string>? activePaths = null;
            try
            {
                if (changedPaths is null)
                {
                    activePaths = ReconcileRoot(
                        fullRoot,
                        rangeStart,
                        now,
                        cancellationToken);
                }
                else
                {
                    targetedRefreshes++;
                    ReconcileChangedPaths(
                        fullRoot,
                        changedPaths,
                        now,
                        cancellationToken);
                }
            }
            catch (DirectoryNotFoundException)
            {
                return LastKnownRange(fullRoot, days);
            }
            catch (UnauthorizedAccessException)
            {
                return LastKnownRange(fullRoot, days);
            }
            catch (IOException)
            {
                return LastKnownRange(fullRoot, days);
            }
            finally
            {
                // A targeted reconcile depends on the complete in-memory index
                // for every unchanged path. Full scans can safely evict because
                // they rebuild the authoritative active-path set first.
                if (changedPaths is null)
                {
                    EvictStaleStates(now);
                }
            }

            var combined = CombineRange(
                fullRoot,
                days,
                activePaths);
            return combined.ResponseCount > 0 ? combined : null;
        }
    }

    private HashSet<string> ReconcileRoot(
        string fullRoot,
        DateOnly rangeStart,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var allPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var activePaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = false,
            ReturnSpecialDirectories = false,
            AttributesToSkip = FileAttributes.ReparsePoint,
        };

        foreach (var path in Directory.EnumerateFiles(fullRoot, "*", options))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!string.Equals(
                    Path.GetExtension(path),
                    ".jsonl",
                    StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var fullPath = Path.GetFullPath(path);
            allPaths.Add(fullPath);
            if (!WasModifiedOnOrAfter(fullPath, rangeStart))
            {
                continue;
            }

            activePaths.Add(fullPath);
            if (states.TryGetValue(fullPath, out var state))
            {
                // Full/manual reconciliation is a truth pass, not merely a
                // metadata poll. Validate fingerprints even when length and
                // timestamp are unchanged.
                state.RequiresIdentityValidation = true;
            }

            _ = UsageForTranscriptLocked(
                fullPath,
                now,
                cancellationToken);
        }

        foreach (var path in states.Keys
                     .Where(path => IsPathBelowRoot(fullRoot, path))
                     .Where(path => !allPaths.Contains(path))
                     .ToArray())
        {
            RemoveState(path, removePersistentCache: true);
        }

        return activePaths;
    }

    private void ReconcileChangedPaths(
        string fullRoot,
        IReadOnlyCollection<string> changedPaths,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        foreach (var path in changedPaths
                     .Where(path => !string.IsNullOrWhiteSpace(path))
                     .Select(Path.GetFullPath)
                     .Distinct(StringComparer.OrdinalIgnoreCase))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!IsPathBelowRoot(fullRoot, path) ||
                !string.Equals(
                    Path.GetExtension(path),
                    ".jsonl",
                    StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (!File.Exists(path))
            {
                RemoveState(path, removePersistentCache: true);
                continue;
            }

            if (states.TryGetValue(path, out var state))
            {
                // A watcher event is positive evidence that the file changed.
                // Do not let an unchanged/coarse timestamp bypass the identity
                // checks for a same-size replacement.
                state.RequiresIdentityValidation = true;
            }

            _ = UsageForTranscriptLocked(
                path,
                now,
                cancellationToken);
        }
    }

    private TokenUsage CombineRange(
        string fullRoot,
        IReadOnlySet<DateOnly> days,
        IReadOnlySet<string>? activePaths)
    {
        var combined = new TokenUsage();
        foreach (var item in states)
        {
            if (!IsPathBelowRoot(fullRoot, item.Key) ||
                activePaths is not null &&
                !activePaths.Contains(item.Key))
            {
                continue;
            }

            var state = item.Value;
            foreach (var day in days)
            {
                if (state.PerDay.TryGetValue(day, out var usage))
                {
                    combined.Add(usage);
                }
            }

            foreach (var pending in state.PendingByDay)
            {
                if (days.Contains(pending.Key.Day))
                {
                    combined.AddAttribution(
                        pending.Key.AgentId,
                        ModelName.Unattributed,
                        pending.Value);
                }
            }
        }

        return combined;
    }

    private TokenUsage? LastKnownRange(
        string fullRoot,
        IReadOnlySet<DateOnly> days)
    {
        var fallback = CombineRange(
            fullRoot,
            days,
            activePaths: null);
        return fallback.ResponseCount > 0 ? fallback : null;
    }

    private static bool IsPathBelowRoot(string fullRoot, string fullPath)
    {
        var relative = Path.GetRelativePath(fullRoot, fullPath);
        return !Path.IsPathRooted(relative) &&
               !string.Equals(relative, "..", StringComparison.Ordinal) &&
               !relative.StartsWith(
                   $"..{Path.DirectorySeparatorChar}",
                   StringComparison.Ordinal) &&
               !relative.StartsWith(
                   $"..{Path.AltDirectorySeparatorChar}",
                   StringComparison.Ordinal);
    }

    private bool WasModifiedOnOrAfter(string path, DateOnly day)
    {
        var modifiedUtc = File.GetLastWriteTimeUtc(path);
        var modified = new DateTimeOffset(modifiedUtc, TimeSpan.Zero);
        return LocalDate(modified) >= day;
    }

    private TokenUsage? UsageForTranscriptLocked(
        string path,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var state = states.TryGetValue(path, out var inMemory)
            ? inMemory
            : TryLoadCachedState(path, now);

        long metadataLength;
        DateTime metadataLastWriteUtc;
        try
        {
            var information = new FileInfo(path);
            information.Refresh();
            if (!information.Exists)
            {
                RemoveState(path, removePersistentCache: true);
                return null;
            }

            metadataLength = information.Length;
            metadataLastWriteUtc = information.LastWriteTimeUtc;
        }
        catch (ArgumentException)
        {
            RemoveState(path, removePersistentCache: true);
            return null;
        }
        catch (FileNotFoundException)
        {
            RemoveState(path, removePersistentCache: true);
            return null;
        }
        catch (DirectoryNotFoundException)
        {
            RemoveState(path, removePersistentCache: true);
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

        if (state is not null &&
            !state.RequiresIdentityValidation &&
            state.ObservedLength == metadataLength &&
            state.ConsumedBytes == metadataLength &&
            state.LastWriteUtc == metadataLastWriteUtc)
        {
            state.LastAccessed = now;
            return ResultFromState(state);
        }

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
            RemoveState(path, removePersistentCache: true);
            return null;
        }
        catch (FileNotFoundException)
        {
            RemoveState(path, removePersistentCache: true);
            return null;
        }
        catch (DirectoryNotFoundException)
        {
            RemoveState(path, removePersistentCache: true);
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
            var persist = false;
            long size;
            try
            {
                size = stream.Length;
                state ??= new ParseState();
                var lastWriteUtc = File.GetLastWriteTimeUtc(path);
                if (size < state.ObservedLength ||
                    size < state.ConsumedBytes ||
                    (size == state.ObservedLength &&
                     state.LastWriteUtc != default &&
                     state.LastWriteUtc != lastWriteUtc) ||
                    !PrefixMatches(stream, state) ||
                    !CheckpointMatches(stream, state))
                {
                    state.PartialLine.Dispose();
                    state = new ParseState();
                    persist = true;
                    if (cacheStore is not null)
                    {
                        cacheInvalidations++;
                        cacheStore.Remove(path);
                    }
                }

                CapturePrefix(stream, state, size);
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
                        contentBytesRead += count;
                        persist = true;
                    }
                }

                CaptureCheckpoint(stream, state, size);
                state.ObservedLength = size;
                state.LastWriteUtc = lastWriteUtc;
                state.LastAccessed = now;
                state.RequiresIdentityValidation = false;
            }
            catch (OperationCanceledException)
            {
                AbandonInterruptedState(path, state);
                throw;
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException)
            {
                AbandonInterruptedState(path, state);
                return null;
            }

            states[path] = state;
            if (persist)
            {
                PersistState(path, state);
            }

            return ResultFromState(state);
        }
    }

    private ParseState? TryLoadCachedState(
        string path,
        DateTimeOffset now)
    {
        if (cacheStore is null)
        {
            return null;
        }

        var result = cacheStore.Load(path);
        if (result.Status == TranscriptTokenCacheLoadStatus.Miss)
        {
            cacheMisses++;
            return null;
        }

        if (result.Status != TranscriptTokenCacheLoadStatus.Loaded ||
            result.Entry is null ||
            !TryRestoreState(result.Entry, now, out var state))
        {
            cacheInvalidations++;
            cacheStore.Remove(path);
            return null;
        }

        cacheLoads++;
        return state;
    }

    private static bool TryRestoreState(
        TranscriptTokenCacheEntry entry,
        DateTimeOffset now,
        out ParseState? state)
    {
        state = null;
        var expectedWindowLength = checked(
            (int)Math.Min(
                entry.ObservedLength,
                FileIdentityCheckpointBytes));
        if (entry.ConsumedBytes > entry.ObservedLength ||
            entry.PrefixOffset != 0 ||
            !IsValidIdentityWindow(
                entry.PrefixLength,
                entry.PrefixHash,
                expectedWindowLength) ||
            !IsValidIdentityWindow(
                entry.CheckpointLength,
                entry.CheckpointHash,
                expectedWindowLength) ||
            entry.CheckpointOffset !=
            entry.ObservedLength - entry.CheckpointLength ||
            entry.SeenResponseIds.Any(
                static identity => !IsSha256Identity(identity)))
        {
            return false;
        }

        var restored = new ParseState
        {
            ConsumedBytes = entry.ConsumedBytes,
            ObservedLength = entry.ObservedLength,
            DroppingOversizedLine = entry.DroppingOversizedLine,
            PrefixLength = entry.PrefixLength,
            PrefixHash = entry.PrefixHash.ToArray(),
            CheckpointOffset = entry.CheckpointOffset,
            CheckpointLength = entry.CheckpointLength,
            CheckpointHash = entry.CheckpointHash.ToArray(),
            ActiveCodexModel = entry.ActiveCodexModel is null
                ? null
                : ModelName.Named(entry.ActiveCodexModel),
            CodexRunningTotal = entry.CodexRunningTotal is null
                ? null
                : new CodexRunningTotal(
                    entry.CodexRunningTotal.DirectInput,
                    entry.CodexRunningTotal.Output,
                    entry.CodexRunningTotal.CacheRead),
            LastAccessed = now,
            LastWriteUtc = entry.LastWriteUtc,
            RequiresIdentityValidation = true,
        };

        if (entry.SeenResponseIds.Distinct(
                StringComparer.Ordinal).Count() !=
            entry.SeenResponseIds.Count)
        {
            restored.PartialLine.Dispose();
            return false;
        }

        foreach (var identity in entry.SeenResponseIds)
        {
            restored.SeenResponseIds.Add(identity);
        }

        restored.Usage.Add(entry.Usage.ToUsage());
        foreach (var item in entry.PerDay)
        {
            if (!restored.PerDay.TryAdd(
                    item.Day,
                    item.Usage.ToUsage()))
            {
                restored.PartialLine.Dispose();
                return false;
            }
        }

        foreach (var item in entry.PendingByAgent)
        {
            if (!restored.PendingByAgent.TryAdd(
                    item.AgentId,
                    item.Usage.ToUsage()))
            {
                restored.PartialLine.Dispose();
                return false;
            }
        }

        foreach (var item in entry.PendingByDay)
        {
            if (!restored.PendingByDay.TryAdd(
                    new PendingUsageKey(item.Day, item.AgentId),
                    item.Usage.ToUsage()))
            {
                restored.PartialLine.Dispose();
                return false;
            }
        }

        state = restored;
        return true;
    }

    private static bool IsValidIdentityWindow(
        int length,
        byte[] hash,
        int expectedLength) =>
        length == expectedLength &&
        (length == 0
            ? hash.Length == 0
            : hash.Length == 32);

    private static bool IsSha256Identity(string identity)
    {
        if (identity.Length != 64)
        {
            return false;
        }

        foreach (var character in identity)
        {
            if (!((character >= '0' && character <= '9') ||
                  (character >= 'A' && character <= 'F')))
            {
                return false;
            }
        }

        return true;
    }

    private void PersistState(string path, ParseState state)
    {
        if (cacheStore is null)
        {
            return;
        }

        var safeConsumedBytes = state.DroppingOversizedLine
            ? state.ConsumedBytes
            : state.ConsumedBytes - state.PartialLine.Length;
        if (safeConsumedBytes < 0 ||
            safeConsumedBytes > state.ObservedLength)
        {
            return;
        }

        var entry = new TranscriptTokenCacheEntry
        {
            ConsumedBytes = safeConsumedBytes,
            ObservedLength = state.ObservedLength,
            LastWriteUtc = state.LastWriteUtc,
            DroppingOversizedLine = state.DroppingOversizedLine,
            PrefixOffset = 0,
            PrefixLength = state.PrefixLength,
            PrefixHash = state.PrefixHash.ToArray(),
            CheckpointOffset = state.CheckpointOffset,
            CheckpointLength = state.CheckpointLength,
            CheckpointHash = state.CheckpointHash.ToArray(),
            SeenResponseIds = state.SeenResponseIds
                .Order(StringComparer.Ordinal)
                .ToList(),
            Usage = TranscriptTokenUsageSnapshot.FromUsage(state.Usage),
            PerDay = state.PerDay
                .OrderBy(item => item.Key)
                .Select(item => new TranscriptDailyUsageSnapshot
                {
                    Day = item.Key,
                    Usage = TranscriptTokenUsageSnapshot.FromUsage(item.Value),
                })
                .ToList(),
            PendingByAgent = state.PendingByAgent
                .OrderBy(item => item.Key)
                .Select(item => new TranscriptPendingAgentUsageSnapshot
                {
                    AgentId = item.Key,
                    Usage = TranscriptTokenUsageSnapshot.FromUsage(item.Value),
                })
                .ToList(),
            PendingByDay = state.PendingByDay
                .OrderBy(item => item.Key.Day)
                .ThenBy(item => item.Key.AgentId)
                .Select(item => new TranscriptPendingDayUsageSnapshot
                {
                    Day = item.Key.Day,
                    AgentId = item.Key.AgentId,
                    Usage = TranscriptTokenUsageSnapshot.FromUsage(item.Value),
                })
                .ToList(),
            ActiveCodexModel = state.ActiveCodexModel?.Value,
            CodexRunningTotal = state.CodexRunningTotal is not { } total
                ? null
                : new TranscriptCodexRunningTotalSnapshot
                {
                    DirectInput = total.DirectInput,
                    Output = total.Output,
                    CacheRead = total.CacheRead,
                },
        };

        if (cacheStore.Save(path, entry))
        {
            cacheWrites++;
        }
    }

    private static TokenUsage? ResultFromState(ParseState state)
    {
        if (state.Usage.ResponseCount == 0)
        {
            return null;
        }

        var result = state.Usage.Clone();
        foreach (var pending in state.PendingByAgent)
        {
            result.AddAttribution(
                pending.Key,
                ModelName.Unattributed,
                pending.Value);
        }

        return result;
    }

    private void RemoveState(
        string path,
        bool removePersistentCache)
    {
        if (states.Remove(path, out var state))
        {
            state.PartialLine.Dispose();
        }

        if (removePersistentCache)
        {
            cacheStore?.Remove(path);
        }
    }

    private void AbandonInterruptedState(
        string path,
        ParseState? state)
    {
        states.TryGetValue(path, out var registered);
        RemoveState(path, removePersistentCache: false);
        if (state is not null &&
            !ReferenceEquals(registered, state))
        {
            state.PartialLine.Dispose();
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

        var current = HashWindow(stream, 0, state.PrefixLength);
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
        if (size <= 0)
        {
            return;
        }

        var prefixLength = checked(
            (int)Math.Min(size, FileIdentityPrefixBytes));
        if (state.PrefixLength == prefixLength &&
            state.PrefixHash.Length > 0)
        {
            return;
        }

        state.PrefixLength = prefixLength;
        state.PrefixHash = HashWindow(stream, 0, state.PrefixLength);
    }

    private static bool CheckpointMatches(FileStream stream, ParseState state)
    {
        if (state.CheckpointHash.Length == 0 ||
            state.CheckpointLength == 0)
        {
            return true;
        }

        if (stream.Length <
            state.CheckpointOffset + state.CheckpointLength)
        {
            return false;
        }

        var current = HashWindow(
            stream,
            state.CheckpointOffset,
            state.CheckpointLength);
        try
        {
            return CryptographicOperations.FixedTimeEquals(
                current,
                state.CheckpointHash);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(current);
        }
    }

    private static void CaptureCheckpoint(
        FileStream stream,
        ParseState state,
        long size)
    {
        if (size <= 0)
        {
            state.CheckpointOffset = 0;
            state.CheckpointLength = 0;
            state.CheckpointHash = [];
            return;
        }

        state.CheckpointLength = checked(
            (int)Math.Min(size, FileIdentityCheckpointBytes));
        state.CheckpointOffset = size - state.CheckpointLength;
        state.CheckpointHash = HashWindow(
            stream,
            state.CheckpointOffset,
            state.CheckpointLength);
    }

    private static byte[] HashWindow(
        FileStream stream,
        long offset,
        int length)
    {
        var originalPosition = stream.Position;
        var buffer = new byte[length];
        try
        {
            stream.Seek(offset, SeekOrigin.Begin);
            var readOffset = 0;
            while (readOffset < buffer.Length)
            {
                var count = stream.Read(
                    buffer,
                    readOffset,
                    buffer.Length - readOffset);
                if (count == 0)
                {
                    throw new EndOfStreamException(
                        "The transcript changed while its identity was checked.");
                }

                readOffset += count;
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
            !state.SeenResponseIds.Add(ResponseIdentity(id)))
        {
            return false;
        }

        usage.InputTokens = Math.Max(ReadInteger(rawUsage, "input_tokens"), 0);
        usage.OutputTokens = Math.Max(ReadInteger(rawUsage, "output_tokens"), 0);
        usage.CacheReadTokens =
            Math.Max(ReadInteger(rawUsage, "cache_read_input_tokens"), 0);

        usage.ResponseCount = 1;
        model = ReadString(message, "model");
        timestamp = ReadString(root, "timestamp");
        return true;
    }

    private static string ResponseIdentity(string responseId) =>
        Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes(responseId)));

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
        var cacheRead = current.CacheRead - previous.CacheRead;

        // A reset or malformed running total contributes nothing, but it still
        // becomes the new baseline. Otherwise every later event would be
        // rejected until the counter climbed back above its former high-water
        // mark.
        if (directInput < 0 ||
            output < 0 ||
            cacheRead < 0)
        {
            state.CodexRunningTotal = current;
            return false;
        }

        state.CodexRunningTotal = current;
        usage.InputTokens = directInput;
        usage.OutputTokens = output;
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
            RemoveState(path, removePersistentCache: false);
        }
    }

    private sealed class ParseState
    {
        public long ConsumedBytes { get; set; }
        public long ObservedLength { get; set; }
        public MemoryStream PartialLine { get; set; } = new();
        public bool DroppingOversizedLine { get; set; }
        public int PrefixLength { get; set; }
        public byte[] PrefixHash { get; set; } = [];
        public long CheckpointOffset { get; set; }
        public int CheckpointLength { get; set; }
        public byte[] CheckpointHash { get; set; } = [];
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
        public bool RequiresIdentityValidation { get; set; }
    }

    private readonly record struct PendingUsageKey(
        DateOnly Day,
        AgentId AgentId);

    private readonly record struct CodexRunningTotal(
        long DirectInput,
        long Output,
        long CacheRead)
    {
        public CodexRunningTotal Subtracting(CodexRunningTotal other) => new(
            Math.Max(DirectInput - other.DirectInput, 0),
            Math.Max(Output - other.Output, 0),
            Math.Max(CacheRead - other.CacheRead, 0));
    }
}
