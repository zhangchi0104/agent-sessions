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
        /// Usage bucketed by local calendar day *and* Model, which is what the
        /// Tokens tab groups by. A file holds about one Model over about one
        /// day, so the richer key costs roughly one entry per file.
        var perDay: [UsageKey: TokenUsage] = [:]
        /// The Model subsequent Codex usage belongs to, carried forward from
        /// the last line that named one. Lives here for the same reason as the
        /// running total: the seek past `consumedBytes` never re-reads it.
        var currentModel: String?
        /// Codex usage seen before the file named any Model. A sub-agent
        /// rollout streams a prefix before its first `turn_context`, and the
        /// file uses exactly one Model, so this is backfilled rather than
        /// stranded — it stays pending until a Model appears, and only counts
        /// as unknown if none ever does.
        var pendingByDay: [String: TokenUsage] = [:]
        /// The last Codex running total seen in this file. It must live here,
        /// beside `consumedBytes`: a poll routinely ends mid-session, and the
        /// seek past `consumedBytes` means the previous total is never re-read.
        /// Clearing it while keeping `consumedBytes` would silently re-count
        /// the whole file — never clear part of a ParseState.
        var codexRunningTotal = CodexRunningTotal()
        /// When a consumer last asked about this file; drives cache eviction.
        var lastAccessed = Date()
    }

    /// Where one bucket of usage belongs: a local calendar day, and the Model
    /// that produced it.
    struct UsageKey: Hashable {
        let day: String
        let model: String
    }

    /// The Model reported for usage no line ever attributed. Only a rollout
    /// that never names a Model at all lands here.
    static let unknownModel = "unknown"

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
    /// Fast pre-filter: only lines carrying usage, or naming the Model that
    /// later usage belongs to, are worth JSON-decoding. Codex names its Model
    /// on lines that carry no usage at all, so a usage-only filter never sees
    /// one — which is why every Codex figure was model-less before this.
    private static let usageMarker = Data("\"input_tokens\"".utf8)
    private static let turnContextMarker = Data("\"turn_context\"".utf8)
    private static let threadSettingsMarker = Data("\"thread_settings\"".utf8)
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

    /// Token usage recorded within `range` (local time), per Model, across
    /// every agent .jsonl under `root` (a Claude projects directory or a Codex
    /// sessions directory). Transcripts are append-only, so a file last
    /// modified before the window opened cannot hold an entry inside it — the
    /// mtime filter is sound, and per-entry timestamps then exclude any older
    /// entries the surviving files still contain. Empty when nothing was
    /// consumed in the window.
    func breakdown(underProjectsRoot root: String, range: TokenRange) -> [String: TokenUsage] {
        // Calendar.current is right for the *boundary* (local midnight); the
        // resulting Date is then keyed through dayKeyFormatter, whose pinned
        // Gregorian calendar shares the local time zone, so the boundary and
        // the entries inside it always map to the same "yyyy-MM-dd" key.
        let startOfToday = range.start()
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [:] }

        // Every day key inside the window, so a range is a sum over its days.
        let windowKeys = Set((0..<range.days).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: startOfToday)
                .map { dayKeyFormatter.string(from: $0) }
        })
        var today: [String: TokenUsage] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  mtime >= startOfToday
            else { continue }
            _ = usage(forTranscriptAt: url.path)
            guard let state = states[url.path] else { continue }
            for (key, usage) in state.perDay where windowKeys.contains(key.day) {
                today[key.model, default: TokenUsage()].add(usage)
            }
            // Usage the file never attributed — no line in it named a Model.
            for (day, pending) in state.pendingByDay where windowKeys.contains(day) {
                today[Self.unknownModel, default: TokenUsage()].add(pending)
            }
        }
        evictStaleStates()
        return today.filter { $0.value.responseCount > 0 }
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

    /// A line either carries usage — a Claude assistant message, or a Codex
    /// `token_count` event — or names the Model that subsequent Codex usage
    /// belongs to.
    private func parse(line: Data, into state: inout ParseState) {
        let carriesUsage = line.range(of: Self.usageMarker) != nil
        let namesModel = line.range(of: Self.turnContextMarker) != nil
            || line.range(of: Self.threadSettingsMarker) != nil
        guard carriesUsage || namesModel else { return }

        // Codex names its Model on `turn_context` and `thread_settings_applied`
        // lines. Carry the most recent one forward: `token_count` events carry
        // no model and no turn id, so the preceding declaration is the only
        // signal, and it must survive into ParseState because a poll routinely
        // ends mid-session.
        if namesModel,
           let entry = try? decoder.decode(CodexModelLine.self, from: line),
           let model = entry.payload?.model ?? entry.payload?.threadSettings?.model {
            adopt(model: model, into: &state)
            return
        }
        guard carriesUsage else { return }

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
            record(response, model: message.model, timestamp: entry.timestamp, into: &state)
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
            record(response, model: state.currentModel, timestamp: entry.timestamp, into: &state)
        }
    }

    private func record(_ response: TokenUsage, model: String?, timestamp: String?, into state: inout ParseState) {
        state.usage.add(response)
        guard let timestamp, let date = parseTimestamp(timestamp) else { return }
        let day = dayKeyFormatter.string(from: date)
        if let model {
            state.perDay[UsageKey(day: day, model: model), default: TokenUsage()].add(response)
        } else {
            // No Model named yet. Hold it by day so a later declaration can
            // backfill it without losing which day it belonged to.
            state.pendingByDay[day, default: TokenUsage()].add(response)
        }
    }

    /// Adopt the Model a line just named, and settle anything that streamed
    /// before it — the prefix belongs to this Model, not to `unknown`.
    private func adopt(model: String, into state: inout ParseState) {
        state.currentModel = model
        guard state.pendingByDay.isEmpty == false else { return }
        for (day, usage) in state.pendingByDay {
            state.perDay[UsageKey(day: day, model: model), default: TokenUsage()].add(usage)
        }
        state.pendingByDay.removeAll()
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
        /// The Model Claude reports on the same line as the usage.
        let model: String?
        let usage: Usage?
    }
    let message: Message?
    let timestamp: String?
}

/// The slice of a Codex line that names the Model. `turn_context` carries it
/// directly; `thread_settings_applied` nests it one level down.
struct CodexModelLine: Decodable {
    struct Payload: Decodable {
        struct ThreadSettings: Decodable { let model: String? }
        let model: String?
        let threadSettings: ThreadSettings?
    }
    let payload: Payload?
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
