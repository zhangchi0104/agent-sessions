//
//  TranscriptParseState.swift
//  TokenStats
//
//  Domain state shared by transcript parsing and restart checkpoints. Runtime
//  framing keeps raw partial bytes in memory; durable state keeps only a safe
//  cursor and the aggregate facts needed to continue the Token Odometer.
//

import Foundation

nonisolated enum TranscriptParsingLimits {
    static let maximumLineBytes = 16 * 1024 * 1024
}

nonisolated enum TranscriptStateError: Error {
    case invalidState
}

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

    var checkedTotalTokens: Int? {
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

    static func compact(_ count: Int, locale: Locale) -> String {
        count.formatted(
            .number
                .notation(.compactName)
                .locale(locale)
        )
    }
}

/// Where one bucket of usage belongs: a local calendar day, and the Model that
/// produced it.
nonisolated struct TranscriptUsageKey: Hashable, Sendable {
    let day: String
    let model: String
}

/// A Codex session's cumulative usage at one point in its rollout, split the
/// way TokenUsage counts: direct input separate from the cache read.
nonisolated struct CodexRunningTotal: Equatable, Sendable {
    var directInput: Int
    var cacheRead: Int
    var output: Int

    init(
        directInput: Int = 0,
        cacheRead: Int = 0,
        output: Int = 0
    ) {
        self.directInput = directInput
        self.cacheRead = cacheRead
        self.output = output
    }

    func subtracting(_ other: CodexRunningTotal) -> CodexRunningTotal? {
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
        return CodexRunningTotal(
            directInput: max(direct.partialValue, 0),
            cacheRead: max(cached.partialValue, 0),
            output: max(emitted.partialValue, 0)
        )
    }
}

/// Restart-safe framing. A normal incomplete line is represented only by its
/// last committed newline; an oversized line also persists how far it was
/// discarded so a restart does not reread an unbounded prefix.
nonisolated enum TranscriptDurableTail: Equatable, Sendable {
    case committed(through: UInt64)
    case discarding(committedThrough: UInt64, observedThrough: UInt64)

    var safeCommittedBytes: UInt64 {
        switch self {
        case .committed(let through):
            through
        case .discarding(let committedThrough, _):
            committedThrough
        }
    }

    var observedBytes: UInt64 {
        switch self {
        case .committed(let through):
            through
        case .discarding(_, let observedThrough):
            observedThrough
        }
    }

    var isDiscardingOversizedLine: Bool {
        if case .discarding = self {
            return true
        }
        return false
    }

    var discardedThroughBytes: UInt64? {
        if case .discarding(_, let observedThrough) = self {
            return observedThrough
        }
        return nil
    }
}

/// Process-only JSONL framing. Storage is private so callers can observe a
/// phase but cannot manufacture an oversized buffer, a backwards discard
/// cursor, or an overflowing cursor. Every mutation goes through one checked
/// transition below.
nonisolated struct TranscriptTail: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case boundary(through: UInt64)
        case buffering(committedThrough: UInt64, partialLine: Data)
        case discarding(committedThrough: UInt64, observedThrough: UInt64)
    }

    private var storage: Phase

    private init(storage: Phase) {
        self.storage = storage
    }

    static var fresh: TranscriptTail {
        TranscriptTail(storage: .boundary(through: 0))
    }

    static func restore(
        _ durable: TranscriptDurableTail
    ) throws -> TranscriptTail {
        switch durable {
        case .committed(let through):
            return TranscriptTail(storage: .boundary(through: through))
        case .discarding(let committedThrough, let observedThrough):
            guard committedThrough < observedThrough,
                  observedThrough - committedThrough
                      > UInt64(TranscriptParsingLimits.maximumLineBytes)
            else {
                throw TranscriptStateError.invalidState
            }
            return TranscriptTail(
                storage: .discarding(
                    committedThrough: committedThrough,
                    observedThrough: observedThrough
                )
            )
        }
    }

    var phase: Phase {
        storage
    }

    var safeCommittedBytes: UInt64 {
        switch storage {
        case .boundary(let through):
            through
        case .buffering(let committedThrough, _),
             .discarding(let committedThrough, _):
            committedThrough
        }
    }

    var observedBytes: UInt64 {
        switch storage {
        case .boundary(let through):
            return through
        case .buffering(let committedThrough, let partialLine):
            // Only `buffer(_:)` can create this case, after checking the sum.
            return committedThrough + UInt64(partialLine.count)
        case .discarding(_, let observedThrough):
            return observedThrough
        }
    }

    var bufferedPartialBytes: Int {
        if case .buffering(_, let partialLine) = storage {
            return partialLine.count
        }
        return 0
    }

    var isDiscardingOversizedLine: Bool {
        if case .discarding = storage {
            return true
        }
        return false
    }

    var discardedThroughBytes: UInt64? {
        if case .discarding(_, let observedThrough) = storage {
            return observedThrough
        }
        return nil
    }

    var durable: TranscriptDurableTail {
        switch storage {
        case .boundary(let through):
            return .committed(through: through)
        case .buffering(let committedThrough, _):
            return .committed(through: committedThrough)
        case .discarding(let committedThrough, let observedThrough):
            return .discarding(
                committedThrough: committedThrough,
                observedThrough: observedThrough
            )
        }
    }

    mutating func buffer(_ partialLine: Data) throws {
        guard partialLine.isEmpty == false,
              partialLine.count <= TranscriptParsingLimits.maximumLineBytes,
              isDiscardingOversizedLine == false
        else {
            throw TranscriptStateError.invalidState
        }
        let observed = safeCommittedBytes.addingReportingOverflow(
            UInt64(partialLine.count)
        )
        guard observed.overflow == false else {
            throw TranscriptStateError.invalidState
        }
        storage = .buffering(
            committedThrough: safeCommittedBytes,
            partialLine: partialLine
        )
    }

    mutating func beginDiscarding(appending byteCount: Int) throws {
        guard byteCount > 0, isDiscardingOversizedLine == false else {
            throw TranscriptStateError.invalidState
        }
        let observed = try checkedObservedBytes(appending: byteCount)
        guard observed - safeCommittedBytes
            > UInt64(TranscriptParsingLimits.maximumLineBytes)
        else {
            throw TranscriptStateError.invalidState
        }
        storage = .discarding(
            committedThrough: safeCommittedBytes,
            observedThrough: observed
        )
    }

    mutating func continueDiscarding(appending byteCount: Int) throws {
        guard case .discarding(let committedThrough, _) = storage,
              byteCount > 0
        else {
            throw TranscriptStateError.invalidState
        }
        storage = .discarding(
            committedThrough: committedThrough,
            observedThrough: try checkedObservedBytes(appending: byteCount)
        )
    }

    mutating func commit(appending byteCount: Int) throws {
        guard byteCount > 0 else {
            throw TranscriptStateError.invalidState
        }
        storage = .boundary(
            through: try checkedObservedBytes(appending: byteCount)
        )
    }

    private func checkedObservedBytes(
        appending byteCount: Int
    ) throws -> UInt64 {
        guard byteCount >= 0 else {
            throw TranscriptStateError.invalidState
        }
        let result = observedBytes.addingReportingOverflow(UInt64(byteCount))
        guard result.overflow == false else {
            throw TranscriptStateError.invalidState
        }
        return result.partialValue
    }
}

/// Codex usage can arrive before its rollout names a Model. The state is
/// either waiting with day-preserving usage or has adopted exactly one Model;
/// the former independent optional Model plus pending dictionary cannot occur.
nonisolated enum TranscriptAttributionState: Equatable, Sendable {
    case pendingUntilModel([String: TokenUsage])
    case model(String)

    var currentModel: String? {
        if case .model(let model) = self {
            return model
        }
        return nil
    }

    var pendingByDay: [String: TokenUsage] {
        if case .pendingUntilModel(let pending) = self {
            return pending
        }
        return [:]
    }
}

/// Parser facts that can safely cross a process restart. Raw paths, response
/// identifiers, and source bytes are intentionally absent.
nonisolated struct TranscriptDurableContinuation: Equatable, Sendable {
    var tail: TranscriptDurableTail
    var seenClaudeResponseHashes: Set<String>
    var usage: TokenUsage
    var perDay: [TranscriptUsageKey: TokenUsage]
    var attribution: TranscriptAttributionState
    var codexRunningTotal: CodexRunningTotal?

    init(
        tail: TranscriptDurableTail,
        seenClaudeResponseHashes: Set<String>,
        usage: TokenUsage,
        perDay: [TranscriptUsageKey: TokenUsage],
        attribution: TranscriptAttributionState,
        codexRunningTotal: CodexRunningTotal?
    ) {
        self.tail = tail
        self.seenClaudeResponseHashes = seenClaudeResponseHashes
        self.usage = usage
        self.perDay = perDay
        self.attribution = attribution
        self.codexRunningTotal = codexRunningTotal
    }
}

/// Mutable state for one transcript parse. It is created fresh or restored from
/// durable facts, then kept behind the per-file reader module.
nonisolated struct TranscriptParserState: Equatable, Sendable {
    private var tail: TranscriptTail
    var seenClaudeResponseHashes: Set<String>
    var usage: TokenUsage
    var perDay: [TranscriptUsageKey: TokenUsage]
    var attribution: TranscriptAttributionState
    var codexRunningTotal: CodexRunningTotal?

    private init(
        tail: TranscriptTail,
        seenClaudeResponseHashes: Set<String>,
        usage: TokenUsage,
        perDay: [TranscriptUsageKey: TokenUsage],
        attribution: TranscriptAttributionState,
        codexRunningTotal: CodexRunningTotal?
    ) {
        self.tail = tail
        self.seenClaudeResponseHashes = seenClaudeResponseHashes
        self.usage = usage
        self.perDay = perDay
        self.attribution = attribution
        self.codexRunningTotal = codexRunningTotal
    }

    static func fresh() -> TranscriptParserState {
        TranscriptParserState(
            tail: .fresh,
            seenClaudeResponseHashes: [],
            usage: TokenUsage(),
            perDay: [:],
            attribution: .pendingUntilModel([:]),
            codexRunningTotal: nil
        )
    }

    static func restore(
        _ continuation: TranscriptDurableContinuation
    ) throws -> TranscriptParserState {
        try TranscriptParserState(
            tail: .restore(continuation.tail),
            seenClaudeResponseHashes: continuation.seenClaudeResponseHashes,
            usage: continuation.usage,
            perDay: continuation.perDay,
            attribution: continuation.attribution,
            codexRunningTotal: continuation.codexRunningTotal
        )
    }

    var durableContinuation: TranscriptDurableContinuation {
        TranscriptDurableContinuation(
            tail: tail.durable,
            seenClaudeResponseHashes: seenClaudeResponseHashes,
            usage: usage,
            perDay: perDay,
            attribution: attribution,
            codexRunningTotal: codexRunningTotal
        )
    }

    var snapshot: TranscriptContinuationSnapshot {
        TranscriptContinuationSnapshot(
            safeCommittedBytes: tail.safeCommittedBytes,
            observedBytes: tail.observedBytes,
            bufferedPartialBytes: tail.bufferedPartialBytes,
            isDiscardingOversizedLine: tail.isDiscardingOversizedLine,
            discardedThroughBytes: tail.discardedThroughBytes
        )
    }

    var reportedUsage: TokenUsage? {
        usage.responseCount > 0 ? usage : nil
    }

    var tailPhase: TranscriptTail.Phase {
        tail.phase
    }

    var observedBytes: UInt64 {
        tail.observedBytes
    }

    mutating func bufferTail(_ partialLine: Data) throws {
        try tail.buffer(partialLine)
    }

    mutating func beginDiscardingTail(appending byteCount: Int) throws {
        try tail.beginDiscarding(appending: byteCount)
    }

    mutating func continueDiscardingTail(appending byteCount: Int) throws {
        try tail.continueDiscarding(appending: byteCount)
    }

    mutating func commitTail(appending byteCount: Int) throws {
        try tail.commit(appending: byteCount)
    }

    func breakdown(
        forDayKeys dayKeys: Set<String>
    ) -> [ModelName: TokenUsage] {
        var result: [ModelName: TokenUsage] = [:]
        for (key, usage) in perDay where dayKeys.contains(key.day) {
            result[.named(key.model), default: TokenUsage()].add(usage)
        }
        for (day, usage) in attribution.pendingByDay
            where dayKeys.contains(day)
        {
            result[.unattributed, default: TokenUsage()].add(usage)
        }
        return result.filter { $0.value.responseCount > 0 }
    }
}
