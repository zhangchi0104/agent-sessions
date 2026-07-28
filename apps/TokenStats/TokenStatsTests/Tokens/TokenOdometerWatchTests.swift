//
//  TokenOdometerWatchTests.swift
//  TokenStatsTests
//
//  Behavior of the popover's Token Odometer under the file-watch refresh
//  model (ADR-0003): it seeds today's total when the popover becomes visible
//  and re-reads when a change is observed, all in-process. Only the OS
//  file-watch boundary is faked; the real TranscriptTokenReader parses real
//  fixture transcripts in a temp directory.
//

import Foundation
import Testing
@testable import TokenStats

@MainActor
struct TokenOdometerWatchTests {
    @Test func seedsTodaysTotalOnActivation() async throws {
        let projects = try TempTranscripts("claude")
        try projects.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])

        let model = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .claudeCode, label: "Test", path: projects.path)]
        )
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.usage?.totalTokens == 150 })
    }

    @Test func reReadsWhenAChangeIsObserved() async throws {
        let projects = try TempTranscripts("claude")
        try projects.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])

        let source = EmittingTicks()
        let model = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .claudeCode, label: "Test", path: projects.path)],
            changeSource: source
        )
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.usage?.totalTokens == 150 })

        try projects.append("a.jsonl", [claudeUsageLine(id: "m2", input: 10, output: 5)])
        source.emit()

        #expect(await waitUntil { model.usage?.totalTokens == 165 })
    }

    @Test func stopsRefreshingAfterCancellation() async throws {
        let projects = try TempTranscripts("claude")
        try projects.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])

        let source = EmittingTicks()
        let model = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .claudeCode, label: "Test", path: projects.path)],
            changeSource: source
        )
        let task = Task { await model.observeWhileVisible() }
        #expect(await waitUntil { model.usage?.totalTokens == 150 })

        task.cancel()
        try? await Task.sleep(for: .milliseconds(50)) // let the loop observe cancellation

        try projects.append("a.jsonl", [claudeUsageLine(id: "m2", input: 10, output: 5)])
        source.emit()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.usage?.totalTokens == 150) // unchanged: watch stopped with the popover
    }

    /// ADR-0003 is "watch only while visible", and the scan is the expensive
    /// half of that. Cancelling has to stop the walk, not merely stop the
    /// result being published — a closed popover must not go on reading roots.
    @Test func aCancelledScanStopsBeforeItsNextRoot() async throws {
        let claude = try TempTranscripts("claude")
        try claude.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])
        let codex = try TempTranscripts("codex")
        try codex.write("rollout.jsonl", [codexTokenCountLine(totalInput: 1_000)])

        let model = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .claudeCode, label: "Claude Code", path: claude.path),
                    TranscriptRoot(id: .codex, label: "Codex", path: codex.path)]
        )
        // Cancelled before the task body runs — the main actor is busy here —
        // so the scan sees cancellation at its very first root boundary.
        let scan = Task { await model.refresh() }
        scan.cancel()
        _ = await scan.value

        #expect(model.hasLoaded == false)
        #expect(model.perAgent.isEmpty)
    }

    /// The four Token Kinds have to land in the four fields the table draws.
    /// Every other Claude fixture leaves both cache kinds at zero, which would
    /// let the two cache columns be swapped without a test noticing.
    @Test func eachClaudeTokenKindLandsInItsOwnColumn() async throws {
        let projects = try TempTranscripts("claude")
        try projects.write("a.jsonl", [
            claudeUsageLine(id: "m1", input: 11, output: 22, cacheWrite: 33, cacheRead: 44),
        ])

        let model = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .claudeCode, label: "Test", path: projects.path)]
        )
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.usage?.totalTokens == 110 })
        let usage = try #require(model.usage)
        #expect(usage.inputTokens == 11)
        #expect(usage.outputTokens == 22)
        #expect(usage.cacheCreationTokens == 33)
        #expect(usage.cacheReadTokens == 44)
    }

    /// A timestamp without fractional seconds still parses. Neither agent
    /// writes one today, so this is the only thing keeping the reader's
    /// fallback from being unreachable code nothing proves works.
    @Test func aTimestampWithoutFractionalSecondsStillBuckets() async throws {
        let projects = try TempTranscripts("claude")
        try projects.write("a.jsonl", [
            claudeUsageLine(id: "m1", input: 100, output: 50, timestamp: nonFractionalStamp()),
        ])

        let model = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .claudeCode, label: "Test", path: projects.path)]
        )
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        // Bucketed into today rather than dropped for want of a parseable day.
        #expect(await waitUntil { model.usage?.totalTokens == 150 })
    }
}
