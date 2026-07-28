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
}
