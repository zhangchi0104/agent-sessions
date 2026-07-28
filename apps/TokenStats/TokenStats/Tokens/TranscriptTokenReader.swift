//
//  TranscriptTokenReader.swift
//  TokenStats
//
//  Sums token usage out of agent JSONL files — Claude Code transcripts and
//  Codex session rollouts; each line's shape decides its parser. Claude
//  assistant entries embed their API response's `usage` and one response can
//  span several lines (one per content block), so totals are deduplicated by
//  message id; Codex `token_count` events carry per-turn deltas that sum
//  directly. Both formats are append-only, so the reader remembers how far it
//  has parsed per file and only reads what was appended since — a re-read
//  stays cheap even for a transcript that has been growing all day.
//

import Foundation

/// Token totals summed across the distinct API responses in one transcript, or
/// across a whole scan root. Cache tokens are tracked separately so the UI can
/// disclose the breakdown.
struct TokenUsage: Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    var cacheReadTokens = 0
    /// Distinct API responses summed; 0 means the file held no usage data
    /// (e.g. a transcript format this reader doesn't understand).
    var responseCount = 0

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
        responseCount += other.responseCount
    }

    /// "1.2M"-style figure for the row label; exact numbers go in the tooltip.
    var compactTotal: String { Self.compact(totalTokens) }

    /// Tooltip phrasing of the in/out split, shared by every surface that
    /// discloses one.
    var breakdownDescription: String {
        "input \((inputTokens + cacheCreationTokens + cacheReadTokens).formatted()) "
            + "(direct \(inputTokens.formatted()), "
            + "cache write \(cacheCreationTokens.formatted()), "
            + "cache read \(cacheReadTokens.formatted())) · "
            + "output \(outputTokens.formatted())"
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
    private struct ParseState {
        var consumedBytes: UInt64 = 0
        /// Bytes after the last newline — an incomplete trailing line.
        var partialLine = Data()
        var seenResponseIDs: Set<String> = []
        var usage = TokenUsage()
        /// Usage bucketed by local calendar day ("yyyy-MM-dd"), for daily sums.
        var perDay: [String: TokenUsage] = [:]
        /// The last Codex running total seen in this file. It must live here,
        /// beside `consumedBytes`: a poll routinely ends mid-session, and the
        /// seek past `consumedBytes` means the previous total is never re-read.
        /// Clearing it while keeping `consumedBytes` would silently re-count
        /// the whole file — never clear part of a ParseState.
        var codexRunningTotal = CodexRunningTotal()
        /// When a consumer last asked about this file; drives cache eviction.
        var lastAccessed = Date()
    }

    /// A Codex session's cumulative usage at one point in its rollout, split
    /// the way TokenUsage counts: direct input separate from the cached part.
    struct CodexRunningTotal: Equatable {
        var directInput = 0
        var cached = 0
        var output = 0

        init() {}

        fileprivate init(_ reported: CodexRolloutLine.Payload.Info.Usage) {
            cached = reported.cachedInputTokens ?? 0
            directInput = max((reported.inputTokens ?? 0) - cached, 0)
            output = reported.outputTokens ?? 0
        }
    }

    private var states: [String: ParseState] = [:]
    private let decoder: JSONDecoder
    private let dayKeyFormatter: DateFormatter
    private let isoTimestamp: ISO8601DateFormatter
    private let isoTimestampFractional: ISO8601DateFormatter
    /// Fast pre-filter: only lines carrying usage are worth JSON-decoding.
    private static let usageMarker = Data("\"input_tokens\"".utf8)
    private static let chunkSize = 4 << 20

    init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Day keys are internal identifiers, never shown: locale and calendar
        // are pinned so a non-Gregorian system calendar can't change the key
        // format, while the default local time zone keeps day boundaries local.
        dayKeyFormatter = DateFormatter()
        dayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFormatter.calendar = Calendar(identifier: .gregorian)
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"
        isoTimestamp = ISO8601DateFormatter()
        isoTimestampFractional = ISO8601DateFormatter()
        isoTimestampFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Token usage recorded *today* (local time) across every agent .jsonl
    /// under `root` (a Claude projects directory or a Codex sessions
    /// directory). Files not modified today can't contain today's entries, so
    /// only today's files are read; per-entry timestamps then exclude any
    /// older entries those files still contain. Nil when nothing was consumed
    /// today.
    func todayUsage(underProjectsRoot root: String) -> TokenUsage? {
        // Calendar.current is right for the *boundary* (local midnight); the
        // resulting Date is then keyed through dayKeyFormatter, whose pinned
        // Gregorian calendar shares the local time zone, so the boundary and
        // the entries inside it always map to the same "yyyy-MM-dd" key.
        let startOfToday = Calendar.current.startOfDay(for: Date())
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        let todayKey = dayKeyFormatter.string(from: startOfToday)
        var today = TokenUsage()
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  mtime >= startOfToday
            else { continue }
            _ = usage(forTranscriptAt: url.path)
            if let day = states[url.path]?.perDay[todayKey] {
                today.add(day)
            }
        }
        evictStaleStates()
        return today.responseCount > 0 ? today : nil
    }

    /// Parse state for files nothing has read in days is archaeology — this
    /// process runs for weeks, and the per-file response-id sets are the bulk
    /// of the memory — so drop entries no consumer is touching anymore.
    private func evictStaleStates() {
        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        states = states.filter { $0.value.lastAccessed > cutoff }
    }

    /// Totals for the transcript at `path`, or nil when the file is missing or
    /// holds no usage entries.
    func usage(forTranscriptAt path: String) -> TokenUsage? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            states[path] = nil
            return nil
        }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }

        var state = states[path] ?? ParseState()
        state.lastAccessed = Date()
        if size < state.consumedBytes {
            // The file shrank — it was replaced or truncated; parse it afresh.
            state = ParseState()
        }

        if size > state.consumedBytes, (try? handle.seek(toOffset: state.consumedBytes)) != nil {
            // Chunked so a first read of a large transcript doesn't buffer the
            // whole file at once.
            while let chunk = try? handle.read(upToCount: Self.chunkSize), chunk.isEmpty == false {
                ingest(chunk, into: &state)
                state.consumedBytes += UInt64(chunk.count)
            }
        }

        states[path] = state
        return state.usage.responseCount > 0 ? state.usage : nil
    }

    private func ingest(_ appended: Data, into state: inout ParseState) {
        var buffer = state.partialLine
        buffer.append(appended)

        var lineStart = buffer.startIndex
        while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
            parse(line: buffer.subdata(in: lineStart..<newline), into: &state)
            lineStart = buffer.index(after: newline)
        }
        state.partialLine = buffer.subdata(in: lineStart..<buffer.endIndex)
    }

    /// A line is either a Claude transcript entry (assistant message with
    /// `usage`) or a Codex rollout `token_count` event; both carry the
    /// "input_tokens" marker the pre-filter looks for.
    private func parse(line: Data, into state: inout ParseState) {
        guard line.range(of: Self.usageMarker) != nil else { return }

        if let entry = try? decoder.decode(TranscriptLine.self, from: line),
           let message = entry.message,
           let usage = message.usage {
            // Count each API response once, however many lines it spans.
            if let id = message.id {
                guard state.seenResponseIDs.insert(id).inserted else { return }
            }
            var response = TokenUsage()
            response.inputTokens = usage.inputTokens ?? 0
            response.outputTokens = usage.outputTokens ?? 0
            response.cacheCreationTokens = usage.cacheCreationInputTokens ?? 0
            response.cacheReadTokens = usage.cacheReadInputTokens ?? 0
            response.responseCount = 1
            record(response, timestamp: entry.timestamp, into: &state)
            return
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
           let running = entry.payload?.info?.totalTokenUsage {
            let previous = state.codexRunningTotal
            let current = CodexRunningTotal(running)
            // The running total is monotonic; guard anyway so a malformed or
            // reset line can never subtract from an established figure.
            var response = TokenUsage()
            response.inputTokens = current.directInput - previous.directInput
            response.cacheReadTokens = current.cached - previous.cached
            response.outputTokens = current.output - previous.output
            guard response.inputTokens >= 0, response.cacheReadTokens >= 0, response.outputTokens >= 0 else { return }
            state.codexRunningTotal = current
            guard response.totalTokens > 0 else { return }
            response.responseCount = 1
            record(response, timestamp: entry.timestamp, into: &state)
        }
    }

    private func record(_ response: TokenUsage, timestamp: String?, into state: inout ParseState) {
        state.usage.add(response)
        if let timestamp, let date = parseTimestamp(timestamp) {
            state.perDay[dayKeyFormatter.string(from: date), default: TokenUsage()].add(response)
        }
    }

    /// Transcript timestamps are ISO 8601, with or without fractional seconds.
    private func parseTimestamp(_ value: String) -> Date? {
        isoTimestampFractional.date(from: value) ?? isoTimestamp.date(from: value)
    }
}

/// The slice of a Claude transcript line the reader cares about.
private struct TranscriptLine: Decodable {
    struct Message: Decodable {
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?
        }
        let id: String?
        let usage: Usage?
    }
    let message: Message?
    let timestamp: String?
}

/// The slice of a Codex rollout line the reader cares about
/// (`{"timestamp", "type": "event_msg", "payload": {"type": "token_count",
///   "info": {"total_token_usage": {...}}}}`). `last_token_usage` is decoded
/// alongside but deliberately unused: it is the field that double-counts.
struct CodexRolloutLine: Decodable {
    struct Payload: Decodable {
        struct Info: Decodable {
            struct Usage: Decodable {
                let inputTokens: Int?
                let cachedInputTokens: Int?
                let outputTokens: Int?
            }
            /// The session's cumulative usage — the figure totals derive from.
            let totalTokenUsage: Usage?
        }
        let type: String?
        let info: Info?
    }
    let payload: Payload?
    let timestamp: String?
}
