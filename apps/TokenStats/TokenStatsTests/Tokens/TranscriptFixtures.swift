//
//  TranscriptFixtures.swift
//  TokenStatsTests
//
//  Shared apparatus for the Tokens tests: a throwaway scan root, line builders
//  for both agent formats, and a poll-until-settled helper. Tests never read
//  the developer's real transcripts — every line here is built in-process and
//  written to a temp directory.
//

import Foundation
@testable import TokenStats

/// A throwaway scan root holding transcript files the reader will parse.
struct TempTranscripts {
    let url: URL
    var path: String { url.path }

    init(_ label: String = "transcripts") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ name: String, _ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n")
            .write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func append(_ name: String, _ lines: [String]) throws {
        let handle = try FileHandle(forWritingTo: url.appendingPathComponent(name))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}

/// Fixture lines land in today's bucket unless aged deliberately.
private func stamp(daysAgo: Int = 0) -> String {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return ISO8601DateFormatter().string(from: date)
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
    daysAgo: Int = 0
) -> String {
    """
    {"timestamp":"\(stamp(daysAgo: daysAgo))","message":{"id":"\(id)","model":"\(model)",\
    "usage":{"input_tokens":\(input),"output_tokens":\(output),\
    "cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead)}}}
    """
}

/// One Codex `token_count` event. Codex reports a *running* total per session;
/// `last_token_usage` is the vendor's own idea of the per-turn delta and is
/// re-emitted verbatim on some turns, which is why the reader derives from the
/// running total instead.
func codexTokenCountLine(
    totalInput: Int,
    totalCached: Int = 0,
    totalOutput: Int = 0,
    lastInput: Int = 0,
    lastCached: Int = 0,
    lastOutput: Int = 0,
    daysAgo: Int = 0
) -> String {
    """
    {"timestamp":"\(stamp(daysAgo: daysAgo))","type":"event_msg","payload":{"type":"token_count",\
    "info":{"total_token_usage":{"input_tokens":\(totalInput),"cached_input_tokens":\(totalCached),\
    "output_tokens":\(totalOutput),"reasoning_output_tokens":0,\
    "total_tokens":\(totalInput + totalOutput)},\
    "last_token_usage":{"input_tokens":\(lastInput),"cached_input_tokens":\(lastCached),\
    "output_tokens":\(lastOutput),"reasoning_output_tokens":0,\
    "total_tokens":\(lastInput + lastOutput)}}}}
    """
}

/// One Codex `turn_context` line — the only place a rollout names its Model.
func codexTurnContextLine(model: String) -> String {
    """
    {"timestamp":"\(stamp())","type":"turn_context",\
    "payload":{"turn_id":"\(UUID().uuidString)","model":"\(model)","cwd":"/tmp"}}
    """
}

/// Stand-in for the OS file-watch: lets a test fire a change tick on demand.
final class EmittingTicks: TranscriptChangeSource, @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() { (stream, continuation) = AsyncStream<Void>.makeStream() }

    func ticks() -> AsyncStream<Void> { stream }
    func emit() { continuation.yield(()) }
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
