//
//  TranscriptJSONLParser.swift
//  TokenStats
//
//  JSONL framing and Coding-Agent-specific transcript parsing. File identity,
//  checkpoint I/O, and retry policy live in TranscriptFileReader.
//

import Foundation

/// Advances one transcript's parser state from contiguous source bytes.
///
/// The interface deliberately accepts only bytes: source stability and
/// checkpoint origin are concerns of TranscriptFileReader, while this module
/// owns line framing, Claude response de-duplication, Codex continuation, and
/// Token Odometer aggregation.
nonisolated struct TranscriptJSONLParser {
    private let decoder: JSONDecoder
    private let dayKeyFormatter: DateFormatter
    private let isoTimestamp: ISO8601DateFormatter
    private let isoTimestampFractional: ISO8601DateFormatter

    /// Fast pre-filter: only lines carrying usage, or naming the Model that
    /// later usage belongs to, are worth JSON-decoding.
    private static let usageMarker = Data("\"input_tokens\"".utf8)
    private static let turnContextMarker = Data("\"turn_context\"".utf8)
    private static let threadSettingsMarker = Data("\"thread_settings\"".utf8)

    init(timeZone: TimeZone) {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        dayKeyFormatter = DateFormatter()
        dayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFormatter.calendar = Calendar(identifier: .gregorian)
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"
        dayKeyFormatter.timeZone = timeZone

        isoTimestamp = ISO8601DateFormatter()
        isoTimestampFractional = ISO8601DateFormatter()
        isoTimestampFractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
    }

    func consume(
        _ appended: Data,
        into state: inout TranscriptParserState,
        statistics: inout TranscriptReadStatistics
    ) throws {
        var cursor = appended.startIndex
        while cursor < appended.endIndex {
            switch state.tailPhase {
            case .discarding:
                guard let newline = appended[cursor...].firstIndex(of: 0x0A) else {
                    try state.continueDiscardingTail(
                        appending: appended.distance(
                            from: cursor,
                            to: appended.endIndex
                        )
                    )
                    return
                }

                let afterNewline = appended.index(after: newline)
                try state.commitTail(
                    appending: appended.distance(
                        from: cursor,
                        to: afterNewline
                    )
                )
                cursor = afterNewline

            case .boundary:
                try consumeRecordSegment(
                    from: &cursor,
                    in: appended,
                    partialLine: Data(),
                    state: &state,
                    statistics: &statistics
                )

            case .buffering(_, let partialLine):
                try consumeRecordSegment(
                    from: &cursor,
                    in: appended,
                    partialLine: partialLine,
                    state: &state,
                    statistics: &statistics
                )
            }
        }
    }

    private func consumeRecordSegment(
        from cursor: inout Data.Index,
        in appended: Data,
        partialLine initialPartialLine: Data,
        state: inout TranscriptParserState,
        statistics: inout TranscriptReadStatistics
    ) throws {
        var partialLine = initialPartialLine
        let newline = appended[cursor...].firstIndex(of: 0x0A)
        let segmentEnd = newline ?? appended.endIndex
        let segmentCount = appended.distance(from: cursor, to: segmentEnd)

        if segmentCount
            > TranscriptParsingLimits.maximumLineBytes - partialLine.count
        {
            if let newline {
                let afterNewline = appended.index(after: newline)
                try state.commitTail(
                    appending: try bytesIncludingNewline(segmentCount)
                )
                cursor = afterNewline
            } else {
                try state.beginDiscardingTail(appending: segmentCount)
                cursor = appended.endIndex
            }
            return
        }

        partialLine.append(contentsOf: appended[cursor..<segmentEnd])
        guard let newline else {
            try state.bufferTail(partialLine)
            cursor = appended.endIndex
            return
        }

        try parse(
            line: partialLine,
            into: &state,
            statistics: &statistics
        )
        try state.commitTail(
            appending: try bytesIncludingNewline(segmentCount)
        )
        cursor = appended.index(after: newline)
    }

    private func bytesIncludingNewline(_ contentBytes: Int) throws -> Int {
        let result = contentBytes.addingReportingOverflow(1)
        guard result.overflow == false else {
            throw TranscriptStateError.invalidState
        }
        return result.partialValue
    }

    /// A line either carries usage — a Claude assistant message, or a Codex
    /// `token_count` event — or names the Model that subsequent Codex usage
    /// belongs to.
    private func parse(
        line: Data,
        into state: inout TranscriptParserState,
        statistics: inout TranscriptReadStatistics
    ) throws {
        let carriesUsage = line.range(of: Self.usageMarker) != nil
        let namesModel = carriesUsage == false
            && (line.range(of: Self.turnContextMarker) != nil
                || line.range(of: Self.threadSettingsMarker) != nil)
        guard carriesUsage || namesModel else { return }
        statistics.jsonLinesSubmittedForDecoding += 1

        if namesModel,
           let entry = try? decoder.decode(CodexModelLine.self, from: line),
           let model = entry.payload?.model
               ?? entry.payload?.threadSettings?.model
        {
            try adopt(model: model, into: &state)
            return
        }
        guard carriesUsage else { return }

        if let entry = try? decoder.decode(TranscriptLine.self, from: line),
           let message = entry.message,
           let usage = message.usage
        {
            if let id = message.id {
                let hash = TranscriptHash.sha256Hex(Data(id.utf8))
                guard state.seenClaudeResponseHashes.insert(hash).inserted else {
                    return
                }
            }

            var response = TokenUsage()
            response.inputTokens = usage.inputTokens ?? 0
            response.outputTokens = usage.outputTokens ?? 0
            response.cacheReadTokens = usage.cacheReadInputTokens ?? 0
            response.responseCount = 1
            try record(
                response,
                model: message.model,
                timestamp: entry.timestamp,
                into: &state
            )
            return
        }

        if let entry = try? decoder.decode(CodexRolloutLine.self, from: line),
           entry.payload?.type == "token_count",
           let running = entry.payload?.info?.totalTokenUsage,
           let current = runningTotal(reported: running)
        {
            let previous = state.codexRunningTotal
                ?? openingBaseline(of: entry.payload?.info, at: current)
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
                state.codexRunningTotal = current
                return
            }

            var response = TokenUsage()
            response.inputTokens = directInput.partialValue
            response.cacheReadTokens = cacheRead.partialValue
            response.outputTokens = output.partialValue
            guard response.inputTokens >= 0,
                  response.cacheReadTokens >= 0,
                  response.outputTokens >= 0
            else {
                // A backwards running total establishes a new baseline but
                // contributes nothing for this event.
                state.codexRunningTotal = current
                return
            }
            state.codexRunningTotal = current
            guard response.totalTokens > 0 else { return }
            response.responseCount = 1
            try record(
                response,
                model: state.attribution.currentModel,
                timestamp: entry.timestamp,
                into: &state
            )
        }
    }

    private func runningTotal(
        reported: CodexRolloutLine.Payload.Info.Usage
    ) -> CodexRunningTotal? {
        let input = reported.inputTokens ?? 0
        let cacheRead = reported.cachedInputTokens ?? 0
        let direct = input.subtractingReportingOverflow(cacheRead)
        guard direct.overflow == false else { return nil }
        return CodexRunningTotal(
            directInput: max(direct.partialValue, 0),
            cacheRead: cacheRead,
            output: reported.outputTokens ?? 0
        )
    }

    /// What a rollout's running total already held before its first event.
    private func openingBaseline(
        of info: CodexRolloutLine.Payload.Info?,
        at current: CodexRunningTotal
    ) -> CodexRunningTotal {
        guard let last = info?.lastTokenUsage,
              let turn = runningTotal(reported: last),
              turn != CodexRunningTotal()
        else {
            return CodexRunningTotal()
        }
        return current.subtracting(turn) ?? CodexRunningTotal()
    }

    private func record(
        _ response: TokenUsage,
        model: String?,
        timestamp: String?,
        into state: inout TranscriptParserState
    ) throws {
        guard let responseTotal = response.checkedTotalTokens else {
            throw TranscriptStateError.invalidState
        }
        guard responseTotal > 0 else { return }

        var aggregate = state.usage
        guard aggregate.add(response) else {
            throw TranscriptStateError.invalidState
        }
        guard let timestamp, let date = parseTimestamp(timestamp) else {
            state.usage = aggregate
            return
        }

        let day = dayKeyFormatter.string(from: date)
        if let model {
            let key = TranscriptUsageKey(day: day, model: model)
            var bucket = state.perDay[key] ?? TokenUsage()
            guard bucket.add(response) else {
                throw TranscriptStateError.invalidState
            }
            state.usage = aggregate
            state.perDay[key] = bucket
            return
        }

        guard case .pendingUntilModel(var pending) = state.attribution else {
            throw TranscriptStateError.invalidState
        }
        var bucket = pending[day] ?? TokenUsage()
        guard bucket.add(response) else {
            throw TranscriptStateError.invalidState
        }
        pending[day] = bucket
        state.usage = aggregate
        state.attribution = .pendingUntilModel(pending)
    }

    /// Adopt the Model a line just named, and settle anything that streamed
    /// before it — the prefix belongs to this Model, not to `unattributed`.
    private func adopt(
        model: String,
        into state: inout TranscriptParserState
    ) throws {
        guard case .pendingUntilModel(let pending) = state.attribution else {
            state.attribution = .model(model)
            return
        }

        var perDay = state.perDay
        for (day, usage) in pending {
            let key = TranscriptUsageKey(day: day, model: model)
            var bucket = perDay[key] ?? TokenUsage()
            guard bucket.add(usage) else {
                throw TranscriptStateError.invalidState
            }
            perDay[key] = bucket
        }
        state.perDay = perDay
        state.attribution = .model(model)
    }

    private func parseTimestamp(_ value: String) -> Date? {
        isoTimestampFractional.date(from: value)
            ?? isoTimestamp.date(from: value)
    }
}

/// The slice of a Claude transcript line the parser cares about.
nonisolated private struct TranscriptLine: Decodable {
    struct Message: Decodable {
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheReadInputTokens: Int?
        }

        let id: String?
        let model: String?
        let usage: Usage?
    }

    let message: Message?
    let timestamp: String?
}

/// A Codex line that can declare the active Model.
nonisolated private struct CodexModelLine: Decodable {
    struct Payload: Decodable {
        struct ThreadSettings: Decodable {
            let model: String?
        }

        let model: String?
        let threadSettings: ThreadSettings?
    }

    let payload: Payload?
}

/// The slice of a Codex rollout event the parser cares about.
nonisolated private struct CodexRolloutLine: Decodable {
    struct Payload: Decodable {
        struct Info: Decodable {
            struct Usage: Decodable {
                let inputTokens: Int?
                let cachedInputTokens: Int?
                let outputTokens: Int?
            }

            let totalTokenUsage: Usage?
            /// The current turn's usage, used only to remove an inherited
            /// baseline from the first running total in a continued rollout.
            let lastTokenUsage: Usage?
        }

        let type: String?
        let info: Info?
    }

    let payload: Payload?
    let timestamp: String?
}
