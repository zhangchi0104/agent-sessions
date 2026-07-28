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
@testable import TokenStats

@MainActor
struct ModelAttributionTests {
    @Test func claudeTokensAreCreditedToTheModelOnTheirOwnLine() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [
            claudeUsageLine(id: "m1", model: "claude-opus-5", input: 100, output: 50),
            claudeUsageLine(id: "m2", model: "claude-haiku-4-5-20251001", input: 10, output: 5),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel["claude-opus-5"]?.totalTokens == 150)
        #expect(byModel["claude-haiku-4-5-20251001"]?.totalTokens == 15)
    }

    @Test func codexTokensAreCreditedToThePrecedingTurnContext() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTurnContextLine(model: "gpt-5.6-sol"),
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel["gpt-5.6-sol"]?.totalTokens == 1_100)
    }

    /// A sub-agent rollout streams usage before it declares its model. The file
    /// uses exactly one model, so that prefix belongs to it — not to `unknown`.
    @Test func usageBeforeTheFirstModelIsBackfilled() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
            codexTurnContextLine(model: "gpt-5.6-sol"),
            codexTokenCountLine(totalInput: 1_500, totalCached: 600, totalOutput: 250),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel["gpt-5.6-sol"]?.totalTokens == 1_750)
        #expect(byModel["unknown"] == nil)
    }

    /// Only a rollout that never names a model at all falls back to `unknown`.
    @Test func aFileThatNeverNamesAModelReportsAsUnknown() async throws {
        let root = try TempTranscripts("codex")
        try root.write("rollout.jsonl", [
            codexTokenCountLine(totalInput: 1_000, totalCached: 400, totalOutput: 100),
        ])

        let byModel = try await breakdown(of: root)
        #expect(byModel["unknown"]?.totalTokens == 1_100)
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
        #expect(byModel["gpt-5.6-sol"]?.totalTokens == 1_000)
        #expect(byModel["codex-auto-review"]?.totalTokens == 600)
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

        let model = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [(label: "Claude Code", path: claude.path), (label: "Codex", path: codex.path)]
        )
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { model.perAgent.count == 2 })
        let byAgent = Dictionary(uniqueKeysWithValues: model.perAgent.map { ($0.label, $0) })
        #expect(byAgent["Claude Code"]?.byModel.first?.model == "claude-opus-5")
        #expect(byAgent["Codex"]?.byModel.first?.model == "gpt-5.6-sol")
        #expect(byAgent["Codex"]?.usage.totalTokens == 1_100)
    }

    // MARK: -

    /// Drives the model over a single root and returns its per-Model slice.
    private func breakdown(of root: TempTranscripts) async throws -> [String: TokenUsage] {
        let model = TokenOdometerModel(reader: TranscriptTokenReader(),
                                     roots: [(label: "Agent", path: root.path)])
        let task = Task { await model.observeWhileVisible() }
        defer { task.cancel() }
        _ = await waitUntil { model.perAgent.isEmpty == false }
        let agent = try #require(model.perAgent.first)
        return Dictionary(uniqueKeysWithValues: agent.byModel.map { ($0.model, $0.usage) })
    }
}
