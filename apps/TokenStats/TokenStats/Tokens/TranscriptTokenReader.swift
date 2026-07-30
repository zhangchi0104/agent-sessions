//
//  TranscriptTokenReader.swift
//  TokenStats
//
//  Sums token usage out of agent JSONL files — Claude Code transcripts and
//  Codex session rollouts; each line's shape decides its parser. Claude
//  assistant entries embed their API response's `usage` and one response can
//  span several lines (one per content block), so totals are deduplicated by
//  message id; Codex `token_count` events carry a *running* session total, and
//  what one event contributed is how far that total advanced — its
//  `last_token_usage` looks like the same figure but is re-emitted verbatim on
//  some turns, so summing it double-counts. Both formats are append-only, so
//  the reader remembers how far it has parsed per file and only reads what was
//  appended since — a re-read stays cheap even for a transcript that has been
//  growing all day.
//

import Darwin
import Foundation

/// Token totals summed across the distinct API responses in one transcript, or
/// across a whole scan root. Cache tokens are tracked separately so the UI can
/// disclose the breakdown.
nonisolated struct TokenUsage: Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    var cacheReadTokens = 0
    /// Distinct API responses summed; 0 means the file held no usage data
    /// (e.g. a transcript format this reader doesn't understand).
    var responseCount = 0

    private var tokenComponents: [Int] {
        [
            inputTokens,
            outputTokens,
            cacheCreationTokens,
            cacheReadTokens,
        ]
    }

    private func summedTokens(saturatingOnOverflow: Bool) -> Int? {
        var total = 0
        for value in tokenComponents {
            let next = total.addingReportingOverflow(value)
            if next.overflow {
                return saturatingOnOverflow
                    ? (value >= 0 ? Int.max : Int.min)
                    : nil
            }
            total = next.partialValue
        }
        return total
    }

    var totalTokens: Int {
        summedTokens(saturatingOnOverflow: true) ?? 0
    }

    fileprivate var checkedTotalTokens: Int? {
        summedTokens(saturatingOnOverflow: false)
    }

    @discardableResult
    mutating func add(_ other: TokenUsage) -> Bool {
        let input = inputTokens.addingReportingOverflow(other.inputTokens)
        let output = outputTokens.addingReportingOverflow(other.outputTokens)
        let cacheCreation = cacheCreationTokens.addingReportingOverflow(
            other.cacheCreationTokens
        )
        let cacheRead = cacheReadTokens.addingReportingOverflow(
            other.cacheReadTokens
        )
        let responses = responseCount.addingReportingOverflow(
            other.responseCount
        )
        guard input.overflow == false,
              output.overflow == false,
              cacheCreation.overflow == false,
              cacheRead.overflow == false,
              responses.overflow == false
        else {
            return false
        }
        inputTokens = input.partialValue
        outputTokens = output.partialValue
        cacheCreationTokens = cacheCreation.partialValue
        cacheReadTokens = cacheRead.partialValue
        responseCount = responses.partialValue
        return true
    }

    static func compact(_ count: Int) -> String {
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (unit, suffix) in units where Double(count) >= unit {
            let scaled = Double(count) / unit
            // One decimal while it's informative ("1.2M"), none once it isn't ("84K").
            let text = scaled < 9.95 ? String(format: "%.1f", scaled) : String(format: "%.0f", scaled)
            return text + suffix
        }
        return String(count)
    }
}

/// Parses transcripts off the main actor and caches per-file progress, so each
/// poll only pays for bytes appended since the previous one.
actor TranscriptTokenReader {
    nonisolated private struct ParseState {
        var continuation = TranscriptDurableContinuation()
        /// The bounded source identity the continuation was derived from.
        var sourceValidation: TranscriptSourceValidation?
        /// Bytes observed by this process. Unlike the durable committed cursor,
        /// this includes an ordinary incomplete tail kept in `partialLine`.
        var observedBytes: UInt64 = 0
        /// Bytes after the last newline — an incomplete trailing line.
        var partialLine = Data()
        /// When a consumer last asked about this file; drives cache eviction.
        var lastAccessed: Date
    }

    nonisolated private struct SourceMetadata: Equatable {
        let device: UInt64
        let inode: UInt64
        let length: UInt64
        let lastWriteSeconds: Int64
        let lastWriteNanoseconds: Int64
    }

    nonisolated private enum TranscriptReadAttemptOutcome {
        case completed(TokenUsage?, TranscriptContinuationSnapshot?)
        case retry
    }

    nonisolated private enum CheckpointLoadOutcome {
        case data(Data)
        case miss
        case invalid
        case unavailable
    }

    nonisolated private enum CheckpointRestoreOutcome {
        case restored(
            TranscriptCheckpoint,
            ValidatedFingerprintMaterial
        )
        case invalid
        case unavailable
    }

    /// Raw fingerprint windows exist only for the duration of one validation.
    /// Keeping them transient lets an append derive its next fingerprints
    /// without another source read.
    nonisolated private struct ValidatedFingerprintMaterial {
        let prefix: Data
        let oldEnd: Data
    }

    nonisolated private enum SourceValidationOutcome {
        case valid(ValidatedFingerprintMaterial)
        case mismatch
        case unavailable
    }

    nonisolated private enum FingerprintReadOutcome {
        case value(Data)
        case mismatch
        case unavailable
    }

    nonisolated private struct FingerprintAccumulator {
        private(set) var prefix: Data
        private(set) var oldEnd: Data
        /// Bytes below this old source end were already represented by the
        /// validated windows. Ordinary partial-tail replay must not append them
        /// to the rolling tail a second time.
        let appendStartsAt: UInt64

        init(
            material: ValidatedFingerprintMaterial?,
            appendStartsAt: UInt64
        ) {
            prefix = material?.prefix ?? Data()
            oldEnd = material?.oldEnd ?? Data()
            self.appendStartsAt = appendStartsAt
        }

        mutating func observe(_ data: Data, startingAt offset: UInt64) {
            let dataEnd = offset + UInt64(data.count)
            guard dataEnd > appendStartsAt else { return }
            let skipped = appendStartsAt > offset
                ? Int(appendStartsAt - offset)
                : 0
            let appended = data[data.index(data.startIndex, offsetBy: skipped)...]

            if prefix.count < TranscriptCheckpointCodec.fingerprintWindowBytes {
                let needed = TranscriptCheckpointCodec.fingerprintWindowBytes - prefix.count
                prefix.append(contentsOf: appended.prefix(needed))
            }

            if appended.count >= TranscriptCheckpointCodec.fingerprintWindowBytes {
                oldEnd = Data(appended.suffix(TranscriptCheckpointCodec.fingerprintWindowBytes))
            } else {
                oldEnd.append(contentsOf: appended)
                if oldEnd.count > TranscriptCheckpointCodec.fingerprintWindowBytes {
                    oldEnd.removeFirst(
                        oldEnd.count - TranscriptCheckpointCodec.fingerprintWindowBytes
                    )
                }
            }
        }

        func sourceValidation(for metadata: SourceMetadata) -> TranscriptSourceValidation? {
            let expectedLength = Int(min(
                metadata.length,
                UInt64(TranscriptCheckpointCodec.fingerprintWindowBytes)
            ))
            guard prefix.count == expectedLength, oldEnd.count == expectedLength else {
                return nil
            }
            return TranscriptSourceValidation(
                sourceLengthAtCheckpoint: metadata.length,
                lastWriteSeconds: metadata.lastWriteSeconds,
                lastWriteNanoseconds: metadata.lastWriteNanoseconds,
                prefixFingerprint: TranscriptFingerprint(
                    offset: 0,
                    length: expectedLength,
                    sha256: TranscriptHash.sha256Hex(prefix)
                ),
                oldEndFingerprint: TranscriptFingerprint(
                    offset: metadata.length - UInt64(expectedLength),
                    length: expectedLength,
                    sha256: TranscriptHash.sha256Hex(oldEnd)
                )
            )
        }
    }

    /// Where one bucket of usage belongs: a local calendar day, and the Model
    /// that produced it.
    nonisolated struct UsageKey: Hashable, Sendable {
        let day: String
        let model: ModelName
    }

    /// A Codex session's cumulative usage at one point in its rollout, split
    /// the way TokenUsage counts: direct input separate from the cache read.
    nonisolated struct CodexRunningTotal: Equatable, Sendable {
        var directInput = 0
        var cacheRead = 0
        var output = 0

        init() {}

        fileprivate init?(
            reported: CodexRolloutLine.Payload.Info.Usage
        ) {
            let input = reported.inputTokens ?? 0
            cacheRead = reported.cachedInputTokens ?? 0
            let direct = input.subtractingReportingOverflow(cacheRead)
            guard direct.overflow == false else { return nil }
            directInput = max(direct.partialValue, 0)
            output = reported.outputTokens ?? 0
        }

        fileprivate func subtracting(
            _ other: CodexRunningTotal
        ) -> CodexRunningTotal? {
            let direct = directInput.subtractingReportingOverflow(
                other.directInput
            )
            let cached = cacheRead.subtractingReportingOverflow(other.cacheRead)
            let emitted = output.subtractingReportingOverflow(other.output)
            guard direct.overflow == false,
                  cached.overflow == false,
                  emitted.overflow == false
            else {
                return nil
            }
            var result = CodexRunningTotal()
            result.directInput = max(direct.partialValue, 0)
            result.cacheRead = max(cached.partialValue, 0)
            result.output = max(emitted.partialValue, 0)
            return result
        }
    }

    private var states: [String: ParseState] = [:]
    private(set) var statistics = TranscriptReadStatistics()
    private let checkpointStore: (any TranscriptCheckpointStoring)?
    private let nowProvider: @Sendable () -> Date
    private let timeZoneIdentifier: String
    private let decoder: JSONDecoder
    private let dayKeyFormatter: DateFormatter
    private let isoTimestamp: ISO8601DateFormatter
    private let isoTimestampFractional: ISO8601DateFormatter
    /// Fast pre-filter: only lines carrying usage, or naming the Model that
    /// later usage belongs to, are worth JSON-decoding. Codex names its Model
    /// on lines that carry no usage at all, so a usage-only filter never sees
    /// one — which is why every Codex figure was model-less before this.
    private static let usageMarker = Data("\"input_tokens\"".utf8)
    private static let turnContextMarker = Data("\"turn_context\"".utf8)
    private static let threadSettingsMarker = Data("\"thread_settings\"".utf8)
    private static let chunkSize = 4 << 20
    private static let maximumLineBytes = 16 << 20

    init(
        checkpointStore: (any TranscriptCheckpointStoring)?
            = TranscriptCheckpointStore.productionDefault,
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.checkpointStore = checkpointStore
        nowProvider = now
        timeZoneIdentifier = timeZone.identifier
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Day keys are internal identifiers, never shown: locale and calendar
        // are pinned so a non-Gregorian system calendar can't change the key
        // format, while the default local time zone keeps day boundaries local.
        dayKeyFormatter = DateFormatter()
        dayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFormatter.calendar = Calendar(identifier: .gregorian)
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"
        dayKeyFormatter.timeZone = timeZone
        isoTimestamp = ISO8601DateFormatter()
        isoTimestampFractional = ISO8601DateFormatter()
        isoTimestampFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Token usage recorded within `range` (local time) as of `now`, per Model,
    /// across every agent .jsonl under `root` (a Claude projects directory or a
    /// Codex sessions directory). Transcripts are append-only, so a file last
    /// modified before the range opened cannot hold an entry inside it — the
    /// mtime filter is sound, and per-entry timestamps then exclude any older
    /// entries the surviving files still contain. Empty when nothing was
    /// consumed in the range.
    ///
    /// `now` is passed in rather than read here so that one refresh resolves
    /// the same span for every Coding Agent: reading the clock per root would
    /// let a scan that straddles local midnight report two agents over two
    /// different days and present them side by side as a comparison.
    func breakdown(underTranscriptRoot root: String, range: TokenRange, now: Date) -> [ModelName: TokenUsage] {
        // Calendar.current is right for the *boundary* (local midnight); the
        // resulting Date is then keyed through dayKeyFormatter, whose pinned
        // Gregorian calendar shares the local time zone, so the boundary and
        // the entries inside it always map to the same "yyyy-MM-dd" key.
        let rangeStart = range.start(from: now)
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [:] }

        // Every day key inside the range, so a range is a sum over its days.
        let dayKeys = Set((0..<range.days).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: rangeStart)
                .map { dayKeyFormatter.string(from: $0) }
        })
        var inRange: [ModelName: TokenUsage] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  mtime >= rangeStart
            else { continue }
            // A large first read is chunked, and each chunk's buffers are
            // autoreleased; without a pool of its own a 30-day scan holds on to
            // every chunk it has ever read until the enumeration returns.
            autoreleasepool { _ = usage(forTranscriptAt: url.path) }
            guard let state = states[url.path] else { continue }
            for (key, usage) in state.continuation.perDay where dayKeys.contains(key.day) {
                inRange[key.model, default: TokenUsage()].add(usage)
            }
            // Usage the file never attributed — no line in it named a Model.
            for (day, pending) in state.continuation.pendingByDay where dayKeys.contains(day) {
                inRange[.unattributed, default: TokenUsage()].add(pending)
            }
        }
        evictStaleStates()
        return inRange.filter { $0.value.responseCount > 0 }
    }

    /// Parse state for files nothing has read in days is archaeology — this
    /// process runs for weeks, and the per-file response-id sets are the bulk
    /// of the memory — so drop entries no consumer is touching anymore.
    private func evictStaleStates() {
        let cutoff = nowProvider().addingTimeInterval(-48 * 60 * 60)
        states = states.filter { $0.value.lastAccessed > cutoff }
    }

    /// Totals for the transcript at `path`, or nil when the file is missing or
    /// holds no usage entries.
    func usage(forTranscriptAt path: String) -> TokenUsage? {
        readTranscript(at: path).usage
    }

    /// Reads one transcript and reports both its totals and deterministic work.
    /// Checkpoints are loaded lazily here, after the authoritative transcript
    /// itself has been encountered and opened.
    func readTranscript(at path: String) -> TranscriptReadResult {
        var readStatistics = TranscriptReadStatistics()
        defer { statistics.add(readStatistics) }

        for attempt in 0..<2 {
            let outcome = readTranscriptAttempt(
                at: path,
                allowCheckpointLoad: attempt == 0,
                forceCheckpointWrite: attempt > 0,
                statistics: &readStatistics
            )
            switch outcome {
            case .completed(let usage, let continuation):
                return TranscriptReadResult(
                    usage: usage,
                    continuation: continuation,
                    statistics: readStatistics
                )
            case .retry:
                // Nothing parsed from an unstable source is allowed to become
                // process state. Reopen the authoritative path once and cold
                // rebuild against the identity now installed there.
                states[path] = nil
            }
        }

        states[path] = nil
        return TranscriptReadResult(
            usage: nil,
            continuation: nil,
            statistics: readStatistics
        )
    }

    private func readTranscriptAttempt(
        at path: String,
        allowCheckpointLoad: Bool,
        forceCheckpointWrite: Bool,
        statistics readStatistics: inout TranscriptReadStatistics
    ) -> TranscriptReadAttemptOutcome {
        let descriptor = Darwin.open(
            path,
            O_RDONLY | O_CLOEXEC | O_NONBLOCK
        )
        guard descriptor >= 0 else {
            states[path] = nil
            return .completed(nil, nil)
        }
        let handle = FileHandle(
            fileDescriptor: descriptor,
            closeOnDealloc: true
        )
        defer { try? handle.close() }
        guard let metadata = sourceMetadata(for: handle) else {
            states[path] = nil
            return .completed(nil, nil)
        }

        let accessedAt = nowProvider()
        let hadInMemoryState = states[path] != nil
        var state = states[path] ?? ParseState(lastAccessed: accessedAt)
        state.lastAccessed = accessedAt
        var fingerprintMaterial: ValidatedFingerprintMaterial?
        var shouldPersist = forceCheckpointWrite

        if allowCheckpointLoad,
           hadInMemoryState == false,
           let checkpointStore
        {
            let loadOutcome = checkpointLoadOutcome(
                from: checkpointStore,
                transcriptPath: path
            )

            guard sourceMetadata(atPath: path) == metadata else {
                switch loadOutcome {
                case .data, .invalid:
                    readStatistics.checkpointInvalidations += 1
                case .miss, .unavailable:
                    break
                }
                return .retry
            }

            switch loadOutcome {
            case .miss:
                readStatistics.checkpointMisses += 1
                shouldPersist = true
            case .invalid:
                readStatistics.checkpointInvalidations += 1
                shouldPersist = true
            case .unavailable:
                // Cache I/O is an optimization boundary. An unavailable cache
                // is neither a miss nor corrupt parser state.
                shouldPersist = true
            case .data(let data):
                let restoreOutcome = checkpointRestoreOutcome(
                    from: data,
                    transcriptPath: path,
                    sourceHandle: handle,
                    metadata: metadata,
                    statistics: &readStatistics
                )
                switch restoreOutcome {
                case .invalid:
                    readStatistics.checkpointInvalidations += 1
                    state = ParseState(lastAccessed: accessedAt)
                    shouldPersist = true
                case .unavailable:
                    return .retry
                case .restored(let checkpoint, let material):
                    guard sourceMetadata(atPath: path) == metadata else {
                        readStatistics.checkpointInvalidations += 1
                        return .retry
                    }

                    state.continuation = checkpoint.continuation
                    state.sourceValidation = checkpoint.source
                    state.partialLine.removeAll(keepingCapacity: false)
                    state.observedBytes = checkpoint.continuation
                        .discardedThroughBytes
                        ?? checkpoint.continuation.safeCommittedBytes
                    fingerprintMaterial = material
                    readStatistics.checkpointLoads += 1
                }
            }
        }

        if let source = state.sourceValidation, fingerprintMaterial == nil {
            let validation = validate(
                source,
                against: handle,
                metadata: metadata,
                statistics: &readStatistics
            )
            switch validation {
            case .valid(let material):
                fingerprintMaterial = material
            case .mismatch:
                if checkpointStore != nil {
                    readStatistics.checkpointInvalidations += 1
                }
                state = ParseState(lastAccessed: accessedAt)
                shouldPersist = true
            case .unavailable:
                return .retry
            }
        }

        if metadata.length < state.observedBytes {
            // The file shrank — it was replaced or truncated; parse it afresh.
            // This path clears the whole state: keeping a cursor across a
            // partial clear silently re-counts or misattributes an entire file.
            if checkpointStore != nil {
                readStatistics.checkpointInvalidations += 1
            }
            state = ParseState(lastAccessed: accessedAt)
            fingerprintMaterial = nil
            shouldPersist = true
        }

        let oldSourceLength = state.sourceValidation?.sourceLengthAtCheckpoint ?? 0
        var fingerprintAccumulator = FingerprintAccumulator(
            material: fingerprintMaterial,
            appendStartsAt: oldSourceLength
        )
        var sourceReadSucceeded = true
        if metadata.length > state.observedBytes {
            do {
                try handle.seek(toOffset: state.observedBytes)
                // Read exactly the source snapshot validated above. An append
                // racing this pass is left for the next scan rather than mixed
                // into the checkpoint currently being published.
                while state.observedBytes < metadata.length {
                    let remaining = metadata.length - state.observedBytes
                    let requested = Int(min(UInt64(Self.chunkSize), remaining))
                    guard let chunk = try handle.read(upToCount: requested),
                          chunk.isEmpty == false
                    else {
                        sourceReadSucceeded = false
                        break
                    }
                    fingerprintAccumulator.observe(
                        chunk,
                        startingAt: state.observedBytes
                    )
                    readStatistics.transcriptContentBytesRead += UInt64(chunk.count)
                    guard ingest(
                        chunk,
                        into: &state,
                        statistics: &readStatistics
                    ) else {
                        if state.sourceValidation != nil,
                           checkpointStore != nil
                        {
                            readStatistics.checkpointInvalidations += 1
                        }
                        sourceReadSucceeded = false
                        break
                    }
                }
            } catch {
                sourceReadSucceeded = false
            }
        }

        guard sourceReadSucceeded,
              let finalMetadata = sourceMetadata(for: handle),
              finalMetadata == metadata,
              sourceMetadata(atPath: path) == finalMetadata,
              state.observedBytes == metadata.length,
              let sourceValidation = fingerprintAccumulator.sourceValidation(
                  for: finalMetadata
              )
        else {
            return .retry
        }

        state.sourceValidation = sourceValidation
        shouldPersist = shouldPersist
            || readStatistics.transcriptContentBytesRead > 0
        states[path] = state

        if shouldPersist, let checkpointStore {
            do {
                let data = try TranscriptCheckpointCodec.encode(
                    TranscriptCheckpoint(
                        source: sourceValidation,
                        continuation: state.continuation
                    ),
                    transcriptPath: path,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                try checkpointStore.publishCheckpoint(data, forTranscriptAt: path)
                readStatistics.checkpointWrites += 1
            } catch {
                // Checkpoints are rebuildable derived data. The authoritative
                // transcript result already lives in memory and remains usable.
            }
        }

        let usage = state.continuation.usage.responseCount > 0
            ? state.continuation.usage
            : nil
        return .completed(usage, continuationSnapshot(for: state))
    }

    private func checkpointLoadOutcome(
        from store: any TranscriptCheckpointStoring,
        transcriptPath: String
    ) -> CheckpointLoadOutcome {
        do {
            guard let data = try store.loadCheckpoint(
                forTranscriptAt: transcriptPath
            ) else {
                return .miss
            }
            return .data(data)
        } catch TranscriptCheckpointStoreError.invalidEntry {
            return .invalid
        } catch {
            return .unavailable
        }
    }

    private func checkpointRestoreOutcome(
        from data: Data,
        transcriptPath: String,
        sourceHandle: FileHandle,
        metadata: SourceMetadata,
        statistics: inout TranscriptReadStatistics
    ) -> CheckpointRestoreOutcome {
        let checkpoint: TranscriptCheckpoint
        do {
            checkpoint = try TranscriptCheckpointCodec.decode(
                data,
                transcriptPath: transcriptPath,
                timeZoneIdentifier: timeZoneIdentifier
            )
        } catch {
            return .invalid
        }

        switch validate(
            checkpoint.source,
            against: sourceHandle,
            metadata: metadata,
            statistics: &statistics
        ) {
        case .valid(let material):
            return .restored(checkpoint, material)
        case .mismatch:
            return .invalid
        case .unavailable:
            return .unavailable
        }
    }

    private func sourceMetadata(for handle: FileHandle) -> SourceMetadata? {
        sourceMetadata(forDescriptor: handle.fileDescriptor)
    }

    private func sourceMetadata(atPath path: String) -> SourceMetadata? {
        let descriptor = Darwin.open(
            path,
            O_RDONLY | O_CLOEXEC | O_NONBLOCK
        )
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        return sourceMetadata(forDescriptor: descriptor)
    }

    private func sourceMetadata(forDescriptor descriptor: Int32) -> SourceMetadata? {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_size >= 0
        else { return nil }
        return SourceMetadata(
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            length: UInt64(status.st_size),
            lastWriteSeconds: Int64(status.st_mtimespec.tv_sec),
            lastWriteNanoseconds: Int64(status.st_mtimespec.tv_nsec)
        )
    }

    private func validate(
        _ source: TranscriptSourceValidation,
        against handle: FileHandle,
        metadata: SourceMetadata,
        statistics: inout TranscriptReadStatistics
    ) -> SourceValidationOutcome {
        guard metadata.length >= source.sourceLengthAtCheckpoint else {
            return .mismatch
        }
        if metadata.length == source.sourceLengthAtCheckpoint {
            guard metadata.lastWriteSeconds == source.lastWriteSeconds,
                  metadata.lastWriteNanoseconds == source.lastWriteNanoseconds
            else { return .mismatch }
        }

        let prefix: Data
        switch readFingerprintWindow(
            source.prefixFingerprint,
            from: handle,
            statistics: &statistics
        ) {
        case .value(let data):
            prefix = data
        case .mismatch:
            return .mismatch
        case .unavailable:
            return .unavailable
        }
        let oldEnd: Data
        switch readFingerprintWindow(
            source.oldEndFingerprint,
            from: handle,
            statistics: &statistics
        ) {
        case .value(let data):
            oldEnd = data
        case .mismatch:
            return .mismatch
        case .unavailable:
            return .unavailable
        }
        guard TranscriptHash.sha256Hex(prefix)
                  == source.prefixFingerprint.sha256,
              TranscriptHash.sha256Hex(oldEnd)
                  == source.oldEndFingerprint.sha256
        else {
            return .mismatch
        }
        guard let finalMetadata = sourceMetadata(for: handle) else {
            return .unavailable
        }
        guard finalMetadata == metadata else {
            return .mismatch
        }
        return .valid(
            ValidatedFingerprintMaterial(prefix: prefix, oldEnd: oldEnd)
        )
    }

    private func readFingerprintWindow(
        _ fingerprint: TranscriptFingerprint,
        from handle: FileHandle,
        statistics: inout TranscriptReadStatistics
    ) -> FingerprintReadOutcome {
        guard fingerprint.length >= 0,
              fingerprint.length <= TranscriptCheckpointCodec.fingerprintWindowBytes,
              fingerprint.offset <= UInt64.max - UInt64(fingerprint.length)
        else { return .mismatch }

        do {
            try handle.seek(toOffset: fingerprint.offset)
            var result = Data()
            while result.count < fingerprint.length {
                let remaining = fingerprint.length - result.count
                guard let chunk = try handle.read(upToCount: remaining),
                      chunk.isEmpty == false
                else { return .mismatch }
                result.append(chunk)
                statistics.fingerprintBytesRead += UInt64(chunk.count)
            }
            return .value(result)
        } catch {
            return .unavailable
        }
    }

    private func continuationSnapshot(
        for state: ParseState
    ) -> TranscriptContinuationSnapshot {
        TranscriptContinuationSnapshot(
            safeCommittedBytes: state.continuation.safeCommittedBytes,
            observedBytes: state.observedBytes,
            bufferedPartialBytes: state.partialLine.count,
            isDiscardingOversizedLine: state.continuation.isDiscardingOversizedLine,
            discardedThroughBytes: state.continuation.discardedThroughBytes
        )
    }

    private func ingest(
        _ appended: Data,
        into state: inout ParseState,
        statistics: inout TranscriptReadStatistics
    ) -> Bool {
        var cursor = appended.startIndex
        while cursor < appended.endIndex {
            if state.continuation.isDiscardingOversizedLine {
                guard let newline = appended[cursor...].firstIndex(of: 0x0A) else {
                    state.observedBytes += UInt64(appended.distance(from: cursor, to: appended.endIndex))
                    state.continuation.discardedThroughBytes = state.observedBytes
                    return true
                }
                let afterNewline = appended.index(after: newline)
                state.observedBytes += UInt64(appended.distance(from: cursor, to: afterNewline))
                state.continuation.safeCommittedBytes = state.observedBytes
                state.continuation.isDiscardingOversizedLine = false
                state.continuation.discardedThroughBytes = nil
                cursor = afterNewline
                continue
            }

            let newline = appended[cursor...].firstIndex(of: 0x0A)
            let segmentEnd = newline ?? appended.endIndex
            let segmentCount = appended.distance(from: cursor, to: segmentEnd)

            if segmentCount > Self.maximumLineBytes - state.partialLine.count {
                state.partialLine.removeAll(keepingCapacity: false)
                state.observedBytes += UInt64(segmentCount)
                if let newline {
                    state.observedBytes += 1
                    state.continuation.safeCommittedBytes = state.observedBytes
                    cursor = appended.index(after: newline)
                } else {
                    state.continuation.isDiscardingOversizedLine = true
                    state.continuation.discardedThroughBytes = state.observedBytes
                    return true
                }
                continue
            }

            state.partialLine.append(contentsOf: appended[cursor..<segmentEnd])
            state.observedBytes += UInt64(segmentCount)
            guard let newline else { return true }

            guard parse(
                line: state.partialLine,
                into: &state,
                statistics: &statistics
            ) else {
                return false
            }
            state.partialLine.removeAll(keepingCapacity: true)
            state.observedBytes += 1
            state.continuation.safeCommittedBytes = state.observedBytes
            cursor = appended.index(after: newline)
        }
        return true
    }

    /// A line either carries usage — a Claude assistant message, or a Codex
    /// `token_count` event — or names the Model that subsequent Codex usage
    /// belongs to.
    private func parse(
        line: Data,
        into state: inout ParseState,
        statistics: inout TranscriptReadStatistics
    ) -> Bool {
        let carriesUsage = line.range(of: Self.usageMarker) != nil
        // A line that carries usage never also names a Model — Codex declares
        // its Model on lines with no usage at all — so the two model markers
        // are only worth scanning for once the usage marker has missed. That
        // keeps a Claude transcript, where neither can ever match, paying one
        // search per line rather than three.
        let namesModel = carriesUsage == false
            && (line.range(of: Self.turnContextMarker) != nil
                || line.range(of: Self.threadSettingsMarker) != nil)
        guard carriesUsage || namesModel else { return true }
        statistics.jsonLinesSubmittedForDecoding += 1

        // Codex names its Model on `turn_context` and `thread_settings_applied`
        // lines. Carry the most recent one forward: `token_count` events carry
        // no model and no turn id, so the preceding declaration is the only
        // signal, and it must survive into ParseState because a poll routinely
        // ends mid-session.
        if namesModel,
           let entry = try? decoder.decode(CodexModelLine.self, from: line),
           let model = entry.payload?.model ?? entry.payload?.threadSettings?.model {
            return adopt(model: model, into: &state)
        }
        guard carriesUsage else { return true }

        if let entry = try? decoder.decode(TranscriptLine.self, from: line),
           let message = entry.message,
           let usage = message.usage {
            // Count each API response once, however many lines it spans.
            if let id = message.id {
                let hash = TranscriptHash.sha256Hex(Data(id.utf8))
                guard state.continuation.seenClaudeResponseHashes
                    .insert(hash).inserted
                else {
                    return true
                }
            }
            var response = TokenUsage()
            response.inputTokens = usage.inputTokens ?? 0
            response.outputTokens = usage.outputTokens ?? 0
            response.cacheCreationTokens = usage.cacheCreationInputTokens ?? 0
            response.cacheReadTokens = usage.cacheReadInputTokens ?? 0
            response.responseCount = 1
            return record(
                response,
                model: message.model.map(ModelName.named),
                timestamp: entry.timestamp,
                into: &state
            )
        }

        // Codex rollout: `total_token_usage` is the session's running total, so
        // what one token_count event contributed is how much that total
        // advanced. `last_token_usage` looks like the same figure but is
        // re-emitted verbatim on some turns — summing it double-counts, which
        // it did until this was corrected. Deriving from the running total is
        // exact and makes a repeat contribute nothing, without the reader
        // deciding whether an event merely looked like a duplicate. Codex's
        // input_tokens INCLUDES the cached portion; split it so totals stay
        // comparable with Claude's (direct + cache read).
        if let entry = try? decoder.decode(CodexRolloutLine.self, from: line),
           entry.payload?.type == "token_count",
           let running = entry.payload?.info?.totalTokenUsage,
           let current = CodexRunningTotal(reported: running)
        {
            let previous = state.continuation.codexRunningTotal ?? openingBaseline(of: entry.payload?.info, at: current)
            let directInput = current.directInput.subtractingReportingOverflow(
                previous.directInput
            )
            let cacheRead = current.cacheRead.subtractingReportingOverflow(
                previous.cacheRead
            )
            let output = current.output.subtractingReportingOverflow(
                previous.output
            )
            guard directInput.overflow == false,
                  cacheRead.overflow == false,
                  output.overflow == false
            else {
                state.continuation.codexRunningTotal = current
                return true
            }
            var response = TokenUsage()
            response.inputTokens = directInput.partialValue
            response.cacheReadTokens = cacheRead.partialValue
            response.outputTokens = output.partialValue
            guard response.inputTokens >= 0, response.cacheReadTokens >= 0, response.outputTokens >= 0 else {
                // The running total went backwards — a reset, or a line this
                // reader misread. Contribute nothing for this event, but adopt
                // the figure as the new baseline: keeping the old one would
                // reject every later event until the total climbed back past
                // its previous high-water mark, silently under-counting the
                // rest of the session instead of just this event.
                state.continuation.codexRunningTotal = current
                return true
            }
            state.continuation.codexRunningTotal = current
            guard response.totalTokens > 0 else { return true }
            response.responseCount = 1
            return record(
                response,
                model: state.continuation.currentCodexModel,
                timestamp: entry.timestamp,
                into: &state
            )
        }
        return true
    }

    /// What a rollout's running total already held before its first event —
    /// tokens some earlier rollout spent and has already been counted for.
    ///
    /// A rollout that continues an earlier session opens with the head it
    /// inherited baked into `total_token_usage`, so starting from zero would
    /// charge this file for the whole parent conversation. The first event's
    /// own contribution is its `last_token_usage`, which makes the head the
    /// difference between the two. This is the *only* use of that field: it is
    /// re-emitted verbatim on later turns, so summing it is what double-counted
    /// before, and nothing here ever adds it to a total.
    ///
    /// A rollout that opens fresh reports the two as equal, leaving a zero
    /// baseline — which is what all but one of the 373 local rollouts do.
    private func openingBaseline(
        of info: CodexRolloutLine.Payload.Info?,
        at current: CodexRunningTotal
    ) -> CodexRunningTotal {
        guard let last = info?.lastTokenUsage,
              let turn = CodexRunningTotal(reported: last)
        else {
            return CodexRunningTotal()
        }
        // An all-zero turn means the field is absent or unpopulated, not that
        // the turn spent nothing — a `token_count` event is only written
        // because something was spent. Reading it as a head would charge this
        // file nothing at all, so treat it as no information and start at zero.
        guard turn != CodexRunningTotal() else { return CodexRunningTotal() }
        return current.subtracting(turn) ?? CodexRunningTotal()
    }

    private func record(
        _ response: TokenUsage,
        model: ModelName?,
        timestamp: String?,
        into state: inout ParseState
    ) -> Bool {
        // A response that spent nothing is not a row. Claude writes `<synthetic>`
        // entries carrying an all-zero usage block, and counting them would put
        // a Model on screen whose every column is a dash.
        guard let responseTotal = response.checkedTotalTokens else {
            return false
        }
        guard responseTotal > 0 else { return true }
        var aggregate = state.continuation.usage
        guard aggregate.add(response) else { return false }
        guard let timestamp, let date = parseTimestamp(timestamp) else {
            state.continuation.usage = aggregate
            return true
        }

        let day = dayKeyFormatter.string(from: date)
        if let model {
            let key = UsageKey(day: day, model: model)
            var bucket = state.continuation.perDay[key] ?? TokenUsage()
            guard bucket.add(response) else { return false }
            state.continuation.usage = aggregate
            state.continuation.perDay[key] = bucket
        } else {
            // No Model named yet. Hold it by day so a later declaration can
            // backfill it without losing which day it belonged to.
            var bucket = state.continuation.pendingByDay[day] ?? TokenUsage()
            guard bucket.add(response) else { return false }
            state.continuation.usage = aggregate
            state.continuation.pendingByDay[day] = bucket
        }
        return true
    }

    /// Adopt the Model a line just named, and settle anything that streamed
    /// before it — the prefix belongs to this Model, not to `unknown`.
    private func adopt(model: String, into state: inout ParseState) -> Bool {
        let model = ModelName.named(model)
        guard state.continuation.pendingByDay.isEmpty == false else {
            state.continuation.currentCodexModel = model
            return true
        }

        var perDay = state.continuation.perDay
        for (day, usage) in state.continuation.pendingByDay {
            let key = UsageKey(day: day, model: model)
            var bucket = perDay[key] ?? TokenUsage()
            guard bucket.add(usage) else { return false }
            perDay[key] = bucket
        }
        state.continuation.currentCodexModel = model
        state.continuation.perDay = perDay
        state.continuation.pendingByDay.removeAll()
        return true
    }

    /// Transcript timestamps are ISO 8601. Both agents write fractional seconds
    /// on every line measured locally; the plain form is kept as a fallback for
    /// a version that does not.
    private func parseTimestamp(_ value: String) -> Date? {
        isoTimestampFractional.date(from: value) ?? isoTimestamp.date(from: value)
    }
}

/// The slice of a Claude transcript line the reader cares about.
nonisolated private struct TranscriptLine: Decodable {
    struct Message: Decodable {
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?
        }
        let id: String?
        /// The Model Claude reports on the same line as the usage.
        let model: String?
        let usage: Usage?
    }
    let message: Message?
    let timestamp: String?
}

/// The slice of a Codex line that names the Model. `turn_context` carries it
/// directly; `thread_settings_applied` nests it one level down.
nonisolated struct CodexModelLine: Decodable {
    struct Payload: Decodable {
        struct ThreadSettings: Decodable { let model: String? }
        let model: String?
        let threadSettings: ThreadSettings?
    }
    let payload: Payload?
}

/// The slice of a Codex rollout line the reader cares about
/// (`{"timestamp", "type": "event_msg", "payload": {"type": "token_count",
///   "info": {"total_token_usage": {...}, "last_token_usage": {...}}}}`).
nonisolated struct CodexRolloutLine: Decodable {
    struct Payload: Decodable {
        struct Info: Decodable {
            struct Usage: Decodable {
                let inputTokens: Int?
                let cachedInputTokens: Int?
                let outputTokens: Int?
            }
            /// The session's cumulative usage — the figure totals derive from.
            let totalTokenUsage: Usage?
            /// The turn's own usage. Summing this is what double-counted, so it
            /// is never added to a total; it is read once, on a file's first
            /// event, to tell an inherited head from a fresh start.
            let lastTokenUsage: Usage?
        }
        let type: String?
        let info: Info?
    }
    let payload: Payload?
    let timestamp: String?
}
