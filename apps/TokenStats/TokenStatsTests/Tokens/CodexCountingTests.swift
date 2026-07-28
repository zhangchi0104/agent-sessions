//
//  CodexCountingTests.swift
//  TokenStatsTests
//
//  What the Token Odometer reports for Codex. Codex rollouts carry a running
//  `total_token_usage` per session alongside a `last_token_usage` the vendor
//  re-emits verbatim on some turns; summing the latter double-counts. These
//  tests pin the contribution of an event to how much the running total
//  advanced, which makes a repeated emission worth nothing.
//

import Foundation
import Testing
@testable import TokenStats

@MainActor
struct CodexCountingTests {
    /// Two events repeating the same `last_token_usage` while the running total
    /// stands still are one turn re-reported, not two turns.
    @Test func repeatedEventContributesNothing() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100,
                                lastInput: 1_000, lastCached: 400, lastOutput: 100),
            // Same turn re-emitted: the running total has not moved.
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100,
                                lastInput: 1_000, lastCached: 400, lastOutput: 100),
        ])

        let model = TokenOdometerModel(reader: TranscriptTokenReader(),
                                     roots: [(label: "Codex", path: root.path)])
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        // 1,000 input of which 400 was cached, plus 100 output — counted once.
        #expect(await waitUntil { model.usage?.totalTokens == 1_100 })
    }

    /// The running total is cumulative, so each event contributes only its own
    /// advance — never the whole total again.
    @Test func successiveEventsContributeTheirAdvanceOnly() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100,
                                lastInput: 1_000, lastCached: 400, lastOutput: 100),
            codexTokenCountLine(totalInput: 1_500, totalCached: 600, totalOutput: 250,
                                lastInput: 500, lastCached: 200, lastOutput: 150),
        ])

        let model = TokenOdometerModel(reader: TranscriptTokenReader(),
                                     roots: [(label: "Codex", path: root.path)])
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.usage?.totalTokens == 1_750 })
    }

    /// Codex's `input_tokens` includes the cached portion; the odometer splits
    /// it so direct input and cache read stay comparable with Claude's.
    @Test func inputSplitsIntoDirectAndCacheRead() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100,
                                lastInput: 1_000, lastCached: 400, lastOutput: 100),
        ])

        let model = TokenOdometerModel(reader: TranscriptTokenReader(),
                                     roots: [(label: "Codex", path: root.path)])
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.usage?.totalTokens == 1_100 })
        let usage = try #require(model.usage)
        #expect(usage.inputTokens == 600)      // 1,000 reported minus 400 cached
        #expect(usage.cacheReadTokens == 400)
        #expect(usage.outputTokens == 100)
        #expect(usage.cacheCreationTokens == 0) // Codex reports no cache writes
    }

    /// Appending to a rollout the reader has already parsed continues from the
    /// remembered running total rather than re-counting the file.
    @Test func resumingAFileDoesNotRecount() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100,
                                lastInput: 1_000, lastCached: 400, lastOutput: 100),
        ])

        let source = EmittingTicks()
        let model = TokenOdometerModel(reader: TranscriptTokenReader(),
                                     roots: [(label: "Codex", path: root.path)],
                                     changeSource: source)
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.usage?.totalTokens == 1_100 })

        try root.append("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_500, totalCached: 600, totalOutput: 250,
                                lastInput: 500, lastCached: 200, lastOutput: 150),
        ])
        source.emit()

        #expect(await waitUntil { model.usage?.totalTokens == 1_750 })
    }
}
