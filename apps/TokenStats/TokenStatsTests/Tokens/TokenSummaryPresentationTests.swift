//
//  TokenSummaryPresentationTests.swift
//  TokenStatsTests
//
//  Objective Tokens-tab summaries. These use every recorded Token Kind and are
//  deliberately independent from the table's selected-kind projection.
//

import Foundation
import SwiftUI
import Testing
@testable import TokenStats

@MainActor
struct TokenSummaryPresentationTests {
    @Test func unloadedSummaryNamesTheRangeBeingRead() {
        let summary = TokenSummaryPresentation.make(
            perAgent: [],
            metric: .billingTokens,
            range: .thirtyDays,
            hasLoaded: false
        )

        #expect(summary.value == "—")
        #expect(summary.label == "Reading 30 days…")
        #expect(summary.numericValue == nil)
    }

    @Test func billingSummaryExcludesOnlyCacheReads() {
        let usage = tokens(input: 10, output: 20, cacheWrite: 30, cacheRead: 9_999)
        let summary = TokenSummaryPresentation.make(
            perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
            metric: .billingTokens,
            range: .today,
            hasLoaded: true
        )

        #expect(summary.value == "60")
        #expect(summary.label == "billing tokens · Today")
        #expect(summary.numericValue == 60)
        #expect(summary.help.contains("Cache read 9,999"))
    }

    @Test func largeBillingSummaryUsesCompactValueButKeepsExactDisclosure() {
        let usage = tokens(input: 12_345_678_901)
        let summary = TokenSummaryPresentation.make(
            perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
            metric: .billingTokens,
            range: .thirtyDays,
            hasLoaded: true
        )

        #expect(summary.value == "12B")
        #expect(summary.numericValue == 12_345_678_901)
        #expect(summary.help.contains("12,345,678,901 billing tokens"))
        #expect(summary.accessibilityLabel.contains("12,345,678,901"))
    }

    @Test func heroHeightIsStableAcrossRangesAndValueLengths() {
        let fixtures: [(TokenRange, TokenUsage)] = [
            (.today, tokens(input: 60)),
            (.sevenDays, tokens(input: 999_999_999)),
            (.thirtyDays, tokens(input: 12_345_678_901)),
        ]

        let heights = fixtures.map { range, usage in
            let hero = TokenSummaryHero(
                perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
                metric: .billingTokens,
                range: range,
                hasLoaded: true
            )
            let controller = NSHostingController(
                rootView: hero.frame(width: 300)
            )
            return controller.sizeThatFits(
                in: CGSize(width: 300, height: 1_000)
            ).height
        }

        #expect(heights.allSatisfy { abs($0 - TokenSummaryHero.fixedHeight) < 0.5 })
    }

    @Test func apiEquivalentUsesTheRecordedAgentAndModel() {
        let usage = tokens(input: 1_000_000)
        let summary = TokenSummaryPresentation.make(
            perAgent: [agent(.codex, model: "gpt-5.6-sol", usage: usage)],
            metric: .apiEquivalent,
            range: .sevenDays,
            hasLoaded: true,
            pricingDate: Date(timeIntervalSince1970: 1_785_283_200)
        )

        #expect(summary.value == "$5.00")
        #expect(summary.label == "API-equivalent · 7 days")
        #expect(summary.numericValue == 5)
    }

    @Test func tokensProjectionExcludesHiddenAgentsFromTheSummary() {
        let claude = agent(.claudeCode, model: "claude-opus-5", usage: tokens(input: 10))
        let codexUsage = tokens(input: 20, output: 30)
        let codex = agent(.codex, model: "gpt-5.6-sol", usage: codexUsage)

        let visible = TokenAgentProjection.visible(
            [claude, codex], inOrder: [.codex]
        )
        let usage = TokenAgentProjection.usage(of: visible)
        let summary = TokenSummaryPresentation.make(
            perAgent: visible,
            metric: .billingTokens,
            range: .today,
            hasLoaded: true
        )

        #expect(visible.map(\.id) == [.codex])
        #expect(usage?.billingTokens == codexUsage.billingTokens)
        #expect(summary.value == "50")
    }

    @Test func unknownModelsStayExplicitlyUnpriced() {
        let usage = tokens(output: 400)
        let summary = TokenSummaryPresentation.make(
            perAgent: [agent(.codex, model: "codex-auto-review", usage: usage)],
            metric: .apiEquivalent,
            range: .today,
            hasLoaded: true
        )

        #expect(summary.value == "—")
        #expect(summary.numericValue == nil)
        #expect(summary.help.contains("Codex: codex-auto-review"))
        #expect(summary.accessibilityLabel.contains("unavailable"))
    }

    private func agent(
        _ id: CodingAgentID,
        model: String,
        usage: TokenUsage
    ) -> TokenOdometerModel.AgentTokens {
        TokenOdometerModel.AgentTokens(
            id: id,
            label: id.integration.displayName,
            usage: usage,
            byModel: [.init(model: .named(model), usage: usage)]
        )
    }

    private func tokens(
        input: Int = 0,
        output: Int = 0,
        cacheWrite: Int = 0,
        cacheRead: Int = 0
    ) -> TokenUsage {
        TokenUsage(
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheWrite,
            cacheReadTokens: cacheRead,
            responseCount: 1
        )
    }
}
