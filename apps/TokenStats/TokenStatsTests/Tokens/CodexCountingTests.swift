//
//  CodexCountingTests.swift
//  TokenStatsTests
//
//  What the Token Odometer reports for Codex. A Codex rollout carries a running
//  `total_token_usage` per session alongside a `last_token_usage` that Codex
//  re-emits verbatim on some turns; summing the latter double-counts. These
//  tests pin the contribution of an event to how much the running total
//  advanced, which makes a repeated emission worth nothing.
//

import Foundation
import Testing

@MainActor
struct CodexCountingTests {
    /// Two events repeating the same `last_token_usage` while the running total
    /// stands still are one turn re-reported, not two turns.
    @Test func repeatedEventContributesNothing() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
            // Same turn re-emitted: the running total has not moved.
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100,
                                lastInput: 1_000, lastCached: 400, lastOutput: 100),
        ])

        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
            changeSource: EmittingTicks()
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        // 1,000 input of which 400 was cached, plus 100 output — counted once.
        #expect(await waitUntil { odometer.usage?.totalTokens == 1_100 })
    }

    /// The running total is cumulative, so each event contributes only its own
    /// advance — never the whole total again.
    @Test func successiveEventsContributeTheirAdvanceOnly() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
            codexTokenCountLine(totalInput: 1_500, totalCached: 600, totalOutput: 250,
                                lastInput: 500, lastCached: 200, lastOutput: 150),
        ])

        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
            changeSource: EmittingTicks()
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.usage?.totalTokens == 1_750 })
    }

    /// Codex's `input_tokens` includes the cached portion; the odometer splits
    /// it so direct input and cache read stay comparable with Claude's.
    @Test func inputSplitsIntoDirectAndCacheRead() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
            changeSource: EmittingTicks()
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.usage?.totalTokens == 1_100 })
        let usage = try #require(odometer.usage)
        #expect(usage.inputTokens == 600)      // 1,000 reported minus 400 cached
        #expect(usage.cacheReadTokens == 400)
        #expect(usage.outputTokens == 100)
        #expect(usage.cacheCreationTokens == 0) // Codex reports no cache writes
    }

    /// A rollout that continues an earlier session opens with that session's
    /// total already in `total_token_usage`. Counting from zero would charge
    /// this file for the whole parent conversation — 7M tokens, in the one
    /// local rollout shaped this way. The first event's own contribution is its
    /// `last_token_usage`, so the head is the difference between the two.
    @Test func aResumedRolloutIsNotChargedForTheHeadItInherited() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100,
                                lastInput: 200, lastCached: 80, lastOutput: 20),
        ])

        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
            changeSource: EmittingTicks()
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        // Its own turn only: 200 input of which 80 cached, plus 20 output.
        #expect(await waitUntil { odometer.usage?.totalTokens == 220 })
        let usage = try #require(odometer.usage)
        #expect(usage.inputTokens == 120)
        #expect(usage.cacheReadTokens == 80)
        #expect(usage.outputTokens == 20)
    }

    /// The running total never decreased in any of the 373 rollouts measured,
    /// so a decrease means a reset or a line this reader misread. The event
    /// itself must contribute nothing — but the rest of the file has to keep
    /// counting. Holding the old baseline would reject every later event until
    /// the total climbed back past its previous high-water mark.
    @Test func aResetRunningTotalStillCountsWhatFollowsIt() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
            // The total falls back — the reset.
            codexTokenCountLine(totalInput: 200, totalCached: 50, totalOutput: 20),
            // …and climbs again, well below the earlier high-water mark.
            codexTokenCountLine(totalInput: 500, totalCached: 100, totalOutput: 60,
                                lastInput: 300, lastCached: 50, lastOutput: 40),
        ])

        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
            changeSource: EmittingTicks()
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        // 1,100 before the reset, then the 340 the third event advanced by.
        #expect(await waitUntil { odometer.usage?.totalTokens == 1_440 })
    }

    /// Appending to a rollout the reader has already parsed continues from the
    /// remembered running total. The count is the same either way — deriving
    /// from a running total is idempotent under a re-parse — so this pins the
    /// event count too, which a re-parse from a cleared baseline would move.
    @Test func resumingAFileContinuesFromTheRememberedTotal() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let source = EmittingTicks()
        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
                                          changeSource: source)
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.usage?.totalTokens == 1_100 })

        try root.append("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_500, totalCached: 600, totalOutput: 250,
                                lastInput: 500, lastCached: 200, lastOutput: 150),
        ])
        source.emit()

        #expect(await waitUntil { odometer.usage?.totalTokens == 1_750 })
        #expect(odometer.usage?.responseCount == 2)
    }

    /// A poll can land mid-line. The tail is carried until the rest of it
    /// arrives, rather than being parsed as a truncated object and dropped.
    @Test func anIncompleteFinalLineIsCarriedUntilItCompletes() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let source = EmittingTicks()
        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
                                          changeSource: source)
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }
        #expect(await waitUntil { odometer.usage?.totalTokens == 1_100 })

        let next = codexTokenCountLine(totalInput: 1_500, totalCached: 600, totalOutput: 250,
                                       lastInput: 500, lastCached: 200, lastOutput: 150)
        let split = next.index(next.startIndex, offsetBy: next.count / 2)
        try root.appendPartial("rollout.jsonl", String(next[..<split]))
        source.emit()
        try? await Task.sleep(for: .milliseconds(120))
        #expect(odometer.usage?.totalTokens == 1_100) // half a line counts for nothing

        try root.appendPartial("rollout.jsonl", String(next[split...]) + "\n")
        source.emit()
        #expect(await waitUntil { odometer.usage?.totalTokens == 1_750 })
    }

    /// A transcript that shrank was replaced or truncated, so the parse state
    /// for it is meaningless and the file is read afresh. This is the one path
    /// allowed to clear a ParseState — and it clears all of it, including
    /// `consumedBytes`, because a half-cleared state re-counts a whole file.
    @Test func aTruncatedFileIsReadAfresh() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
            codexTokenCountLine(totalInput: 1_500, totalCached: 600, totalOutput: 250,
                                lastInput: 500, lastCached: 200, lastOutput: 150),
        ])

        let source = EmittingTicks()
        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
                                          changeSource: source)
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }
        #expect(await waitUntil { odometer.usage?.totalTokens == 1_750 })

        // Replaced by a shorter rollout at the same path.
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 300, totalCached: 100, totalOutput: 40),
        ])
        source.emit()

        #expect(await waitUntil { odometer.usage?.totalTokens == 340 })
    }
}
