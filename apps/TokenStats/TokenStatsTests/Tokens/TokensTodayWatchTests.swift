//
//  TokensTodayWatchTests.swift
//  TokenStatsTests
//
//  Behavior of the popover's Tokens Today figure under the file-watch refresh
//  model (ADR-0003): it seeds today's total when the popover becomes visible
//  and re-reads when a change is observed, all in-process. Only the OS
//  file-watch boundary is faked; the real TranscriptTokenReader parses real
//  fixture transcripts in a temp directory.
//

import Foundation
import Testing
@testable import TokenStats

@MainActor
struct TokensTodayWatchTests {
    @Test func seedsTodaysTotalOnActivation() async throws {
        let projects = try TempProjects()
        try projects.write("a.jsonl", [usageLine(id: "m1", input: 100, output: 50)])

        let model = TokensTodayModel(
            reader: TranscriptTokenReader(),
            roots: [(label: "Test", path: projects.path)]
        )
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.usage?.totalTokens == 150 })
    }

    @Test func reReadsWhenAChangeIsObserved() async throws {
        let projects = try TempProjects()
        try projects.write("a.jsonl", [usageLine(id: "m1", input: 100, output: 50)])

        let source = EmittingChangeSource()
        let model = TokensTodayModel(
            reader: TranscriptTokenReader(),
            roots: [(label: "Test", path: projects.path)],
            changeSource: source
        )
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.usage?.totalTokens == 150 })

        try projects.append("a.jsonl", [usageLine(id: "m2", input: 10, output: 5)])
        source.emit()

        #expect(await waitUntil { model.usage?.totalTokens == 165 })
    }

    @Test func stopsRefreshingAfterCancellation() async throws {
        let projects = try TempProjects()
        try projects.write("a.jsonl", [usageLine(id: "m1", input: 100, output: 50)])

        let source = EmittingChangeSource()
        let model = TokensTodayModel(
            reader: TranscriptTokenReader(),
            roots: [(label: "Test", path: projects.path)],
            changeSource: source
        )
        let task = Task { await model.observeWhileVisible() }
        #expect(await waitUntil { model.usage?.totalTokens == 150 })

        task.cancel()
        try? await Task.sleep(for: .milliseconds(50)) // let the loop observe cancellation

        try projects.append("a.jsonl", [usageLine(id: "m2", input: 10, output: 5)])
        source.emit()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.usage?.totalTokens == 150) // unchanged: watch stopped with the popover
    }
}

/// Stand-in for the OS file-watch: lets a test fire a change tick on demand.
private final class EmittingChangeSource: TranscriptChangeSource, @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    func ticks() -> AsyncStream<Void> { stream }
    func emit() { continuation.yield(()) }
}

// MARK: - Fixtures

/// A throwaway projects root holding transcript files the reader will scan.
private struct TempProjects {
    let url: URL
    var path: String { url.path }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokens-today-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ name: String, _ lines: [String]) throws {
        let body = lines.joined(separator: "\n") + "\n"
        try body.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func append(_ name: String, _ lines: [String]) throws {
        let handle = try FileHandle(forWritingTo: url.appendingPathComponent(name))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}

/// One assistant transcript line carrying a usage block, timestamped now so it
/// falls in today's bucket.
private func usageLine(id: String, input: Int, output: Int) -> String {
    let ts = ISO8601DateFormatter().string(from: Date())
    return #"{"timestamp":"\#(ts)","message":{"id":"\#(id)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
}

/// Polls a main-actor predicate up to ~3s so an async refresh can land.
@MainActor
private func waitUntil(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<300 {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return predicate()
}
