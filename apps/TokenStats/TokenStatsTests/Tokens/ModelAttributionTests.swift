//
//  ModelAttributionTests.swift
//  TokenStatsTests
//
//  Which Model the Token Odometer credits each token to. Claude names the
//  Model on the same line as the usage, so attribution is free. Codex does
//  not: `token_count` events carry no model, and the rollout names it on
//  separate `turn_context` lines — so the reader carries the most recent one
//  forward, and backfills whatever streamed before the first.
//

import Foundation
import Testing

@MainActor
struct ModelAttributionTests {
    @Test func claudeTokensAreCreditedToTheModelOnTheirOwnLine() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [
            claudeUsageLine(id: "m1", model: "claude-opus-5", input: 100, output: 50),
            claudeUsageLine(id: "m2", model: "claude-haiku-4-5-20251001", input: 10, output: 5),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.named("claude-opus-5")]?.totalTokens == 150)
        #expect(byModel[.named("claude-haiku-4-5-20251001")]?.totalTokens == 15)
    }

    @Test func codexTokensAreCreditedToThePrecedingTurnContext() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTurnContextLine(model: "gpt-5.6-sol"),
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.named("gpt-5.6-sol")]?.totalTokens == 1_100)
    }

    /// `thread_settings_applied` is the other carrier, and nests the Model one
    /// level deeper. A rollout that only ever uses it must still attribute.
    @Test func threadSettingsAlsoNamesTheModel() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexThreadSettingsLine(model: "codex-auto-review"),
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.named("codex-auto-review")]?.totalTokens == 1_100)
        #expect(byModel[.unattributed] == nil)
    }

    /// A sub-agent rollout streams usage before it declares its model. Such a
    /// rollout names one model throughout, so that prefix belongs to it rather
    /// than sitting unattributed.
    @Test func usageBeforeTheFirstModelIsBackfilled() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
            codexTurnContextLine(model: "gpt-5.6-sol"),
            codexTokenCountLine(totalInput: 1_500, totalCached: 600, totalOutput: 250),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.named("gpt-5.6-sol")]?.totalTokens == 1_750)
        #expect(byModel[.unattributed] == nil)
    }

    /// Only a rollout that never names a model at all is left unattributed —
    /// which is a distinct case, not the string "unknown", so a rollout that
    /// genuinely names a model called `unknown` stays telling the truth.
    @Test func aFileThatNeverNamesAModelIsLeftUnattributed() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.unattributed]?.totalTokens == 1_100)
    }

    @Test func aLaterTurnContextRedirectsSubsequentUsage() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTurnContextLine(model: "gpt-5.6-sol"),
            codexTokenCountLine(totalInput: 1_000, totalCached: 0, totalOutput: 0),
            codexTurnContextLine(model: "codex-auto-review"),
            codexTokenCountLine(totalInput: 1_600, totalCached: 0, totalOutput: 0),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.named("gpt-5.6-sol")]?.totalTokens == 1_000)
        #expect(byModel[.named("codex-auto-review")]?.totalTokens == 600)
    }

    /// The published breakdown groups by Coding Agent before Model.
    @Test func theModelPublishesABreakdownPerAgent() async throws {
        let claude = try TempTranscripts("claude")
        try claude.write("a.jsonl", [claudeUsageLine(id: "m1", model: "claude-opus-5", input: 100, output: 50)])
        let codex = try TempTranscripts("codex")
        try codex.write("rollout.jsonl", [
            codexTurnContextLine(model: "gpt-5.6-sol"),
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .claudeCode, label: "Claude Code", path: claude.path),
                    TranscriptRoot(id: .codex, label: "Codex", path: codex.path)],
            changeSource: EmittingTicks()
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.perAgent.count == 2 })
        let byAgent = Dictionary(uniqueKeysWithValues: odometer.perAgent.map { ($0.label, $0) })
        #expect(byAgent["Claude Code"]?.byModel.first?.model == .named("claude-opus-5"))
        #expect(byAgent["Codex"]?.byModel.first?.model == .named("gpt-5.6-sol"))
        #expect(byAgent["Codex"]?.usage.totalTokens == 1_100)
    }

    /// The Model is carried in ParseState precisely because a poll can end
    /// between the line that names it and the usage it belongs to. Re-reading
    /// seeks past `consumedBytes`, so if the Model did not survive the poll the
    /// appended tokens would land unattributed instead.
    @Test func theModelSurvivesAPollBoundary() async throws {
        let root = try TempTranscripts("codex")
        try root.write("2026/07/rollout.jsonl", [codexTurnContextLine(model: "gpt-5.6-sol")])

        let source = EmittingTicks()
        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .codex, label: "Codex", path: root.path)],
            changeSource: source
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }
        #expect(await waitUntil { odometer.hasLoaded })

        // A separate poll, after the turn_context line was already consumed.
        try root.append("2026/07/rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])
        source.emit()

        #expect(await waitUntil { odometer.usage?.totalTokens == 1_100 })
        let agent = try #require(odometer.perAgent.first)
        #expect(agent.byModel.map(\.model) == [.named("gpt-5.6-sol")])
    }

    /// One response spans several transcript lines, one per content block, and
    /// each repeats the whole usage block. Without the message-id guard the
    /// same response counts once per line.
    @Test func aResponseSpanningSeveralLinesCountsOnce() async throws {
        let root = try TempTranscripts("claude")
        try root.write("project-a/a.jsonl", [
            claudeUsageLine(id: "m1", input: 100, output: 50),
            claudeUsageLine(id: "m1", input: 100, output: 50),
            claudeUsageLine(id: "m1", input: 100, output: 50),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.named("claude-opus-5")]?.totalTokens == 150)
        #expect(byModel[.named("claude-opus-5")]?.responseCount == 1)
    }

    /// Claude nests one directory per project and Codex one per day, so the
    /// scan root is never where the transcripts actually sit.
    @Test func transcriptsAreFoundInNestedDirectories() async throws {
        let root = try TempTranscripts("claude")
        try root.write("project-a/deep/a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.named("claude-opus-5")]?.totalTokens == 150)
    }

    /// The reader keeps the Model from the transcript, whatever it is called.
    /// `<synthetic>` entries carry an all-zero usage block, and counting them
    /// would put a Model on screen whose every column is a dash.
    @Test func aResponseThatSpentNothingIsNotARow() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [
            claudeUsageLine(id: "m1", model: "claude-opus-5", input: 100, output: 50),
            claudeUsageLine(id: "s1", model: "<synthetic>", input: 0, output: 0),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel[.named("claude-opus-5")]?.totalTokens == 150)
        #expect(byModel[.named("<synthetic>")] == nil)
    }

    /// The id on a scan root exists so the popover can re-order agents into the
    /// user's Appearance order rather than the registry's.
    @Test func agentsArePublishedInTheUsersDisplayOrder() async throws {
        let claude = try TempTranscripts("claude")
        try claude.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])
        let codex = try TempTranscripts("codex")
        try codex.write("rollout.jsonl", [
            codexTurnContextLine(model: "gpt-5.6-sol"),
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [TranscriptRoot(id: .claudeCode, label: "Claude Code", path: claude.path),
                    TranscriptRoot(id: .codex, label: "Codex", path: codex.path)],
            changeSource: EmittingTicks()
        )
        // Registry order is Claude Code first; this user put Codex there.
        odometer.displayOrder = [.codex, .claudeCode]
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.perAgent.count == 2 })
        #expect(odometer.perAgent.map(\.label) == ["Codex", "Claude Code"])
    }
}
