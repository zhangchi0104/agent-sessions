//
//  TranscriptFixtures.swift
//  TokenStatsTests
//
//  Shared apparatus for the Tokens tests: a throwaway scan root, line builders
//  for both agent formats, and a poll-until-settled helper. Tests never read
//  the developer's real transcripts — every line here is built in-process and
//  written to a temp directory.
//
//  The builders are meant to be faithful to what the agents actually write,
//  because a fixture that lies makes every test using it meaningless. Both
//  agents timestamp with fractional seconds on every line measured locally
//  (17,524 of 17,524 Codex events; 15,494 of 15,494 Claude usage lines), and a
//  Codex rollout's first `token_count` reports `last_token_usage` equal to
//  `total_token_usage` in 372 of 373 rollouts — so those are the defaults here.
//

import Foundation

/// A throwaway scan root holding transcript files the reader will parse.
struct TempTranscripts {
    let url: URL
    var path: String { url.path }

    init(_ label: String = "transcripts") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes a transcript. `name` may carry subdirectories — both agents nest
    /// (Claude one directory per project, Codex one per day), so a fixture that
    /// only ever writes at the root leaves the recursive walk uncovered.
    func write(_ name: String, _ lines: [String]) throws {
        let file = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)
    }

    func append(_ name: String, _ lines: [String]) throws {
        let handle = try FileHandle(forWritingTo: url.appendingPathComponent(name))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    /// Appends without a trailing newline, leaving the reader an incomplete
    /// final line to carry in `partialLine` until the rest arrives.
    func appendPartial(_ name: String, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: url.appendingPathComponent(name))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}

/// Fixture lines land in today's bucket unless aged deliberately. Both agents
/// write fractional seconds, so that is what the builders emit — the reader's
/// non-fractional fallback is exercised by `nonFractionalStamp`.
func stamp(daysAgo: Int = 0) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: aged(daysAgo))
}

/// The shape neither agent writes today, kept so the reader's fallback parse
/// has coverage rather than being dead code nothing proves is reachable.
func nonFractionalStamp(daysAgo: Int = 0) -> String {
    ISO8601DateFormatter().string(from: aged(daysAgo))
}

private func aged(_ daysAgo: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
}

/// One Claude assistant transcript line carrying a usage block. `model` is the
/// value Claude reports on the same line as the usage.
func claudeUsageLine(
    id: String,
    model: String = "claude-opus-5",
    input: Int = 0,
    output: Int = 0,
    cacheWrite: Int = 0,
    cacheRead: Int = 0,
    daysAgo: Int = 0,
    timestamp: String? = nil
) -> String {
    """
    {"timestamp":"\(timestamp ?? stamp(daysAgo: daysAgo))","message":{"id":"\(id)","model":"\(model)",\
    "usage":{"input_tokens":\(input),"output_tokens":\(output),\
    "cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead)}}}
    """
}

/// One Codex `token_count` event. Codex reports a *running* total per session;
/// `last_token_usage` is that agent's own idea of the per-turn delta and is
/// re-emitted verbatim on some turns, which is why the reader derives each
/// contribution from how far the running total advanced instead.
///
/// The `last…` figures default to the running total, which is what a rollout's
/// first event reports when it opens fresh. Passing smaller ones models a
/// rollout that continues an earlier session and inherited its head.
func codexTokenCountLine(
    totalInput: Int,
    totalCached: Int = 0,
    totalOutput: Int = 0,
    lastInput: Int? = nil,
    lastCached: Int? = nil,
    lastOutput: Int? = nil,
    daysAgo: Int = 0
) -> String {
    let lastIn = lastInput ?? totalInput
    let lastCache = lastCached ?? totalCached
    let lastOut = lastOutput ?? totalOutput
    return """
    {"timestamp":"\(stamp(daysAgo: daysAgo))","type":"event_msg","payload":{"type":"token_count",\
    "info":{"total_token_usage":{"input_tokens":\(totalInput),"cached_input_tokens":\(totalCached),\
    "output_tokens":\(totalOutput),"reasoning_output_tokens":\(totalOutput),\
    "total_tokens":\(totalInput + totalOutput)},\
    "last_token_usage":{"input_tokens":\(lastIn),"cached_input_tokens":\(lastCache),\
    "output_tokens":\(lastOut),"reasoning_output_tokens":\(lastOut),\
    "total_tokens":\(lastIn + lastOut)}}}}
    """
}

/// One Codex `thread_settings_applied` event — the other line that names a
/// Model, nesting it a level deeper than `turn_context` does.
func codexThreadSettingsLine(model: String, daysAgo: Int = 0) -> String {
    """
    {"timestamp":"\(stamp(daysAgo: daysAgo))","type":"event_msg",\
    "payload":{"type":"thread_settings_applied",\
    "thread_settings":{"model":"\(model)","model_provider_id":"openai"}}}
    """
}

/// One Codex `turn_context` line — the more common of the two carriers.
func codexTurnContextLine(model: String, daysAgo: Int = 0) -> String {
    """
    {"timestamp":"\(stamp(daysAgo: daysAgo))","type":"turn_context",\
    "payload":{"turn_id":"\(UUID().uuidString)","model":"\(model)","cwd":"/tmp"}}
    """
}

/// Stand-in for the OS file-watch: lets a test fire a change tick on demand.
/// Each `ticks()` call gets its own stream, so a test can drive a second
/// appearance of the tab the way the real FSEvents source would.
final class EmittingTicks: TranscriptChangeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<Void>.Continuation] = []

    func ticks() -> AsyncStream<Void> {
        AsyncStream<Void> { continuation in
            lock.lock()
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func emit() {
        lock.lock()
        let live = continuations
        lock.unlock()
        for continuation in live { continuation.yield(()) }
    }
}

/// Polls a main-actor predicate up to ~3s so an async refresh can land.
@MainActor
func waitUntil(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<300 {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return predicate()
}

/// Drives an odometer over one scan root and returns its per-Model slice. The
/// seam every Tokens test uses: a real reader over fixture transcripts, with
/// only the OS file-watch faked.
@MainActor
func breakdown(
    of root: TempTranscripts,
    id: CodingAgentID = .claudeCode,
    range: TokenRange = .today
) async throws -> [ModelName: TokenUsage] {
    let odometer = TokenOdometerModel(
        reader: TranscriptTokenReader(),
        roots: [TranscriptRoot(id: id, label: "Agent", path: root.path)],
        changeSource: EmittingTicks()
    )
    let task = Task { await odometer.observeWhileVisible() }
    defer { task.cancel() }
    _ = await waitUntil { odometer.hasLoaded }
    if range != .today {
        odometer.select(range)
        _ = await waitUntil { odometer.displayedRange == range }
    }
    guard let agent = odometer.perAgent.first else { return [:] }
    return Dictionary(uniqueKeysWithValues: agent.byModel.map { ($0.model, $0.usage) })
}
