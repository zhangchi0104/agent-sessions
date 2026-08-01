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
    private let englishLocale = Locale(identifier: "en-US")

    @Test func unloadedSummaryNamesTheRangeBeingRead() {
        let summary = TokenSummaryPresentation.make(
            perAgent: [],
            metric: .billingTokens,
            range: .thirtyDays,
            hasLoaded: false,
            locale: englishLocale
        )

        #expect(summary.value == "—")
        #expect(summary.label == "Reading 30 days…")
        #expect(summary.numericValue == nil)
    }

    @Test func currentDayUsesAContextualSentenceFormInsteadOfThePickerTitle() {
        let localizer = AppLocalizer(locale: englishLocale)
        let summary = TokenSummaryPresentation.make(
            perAgent: [],
            metric: .billingTokens,
            range: .today,
            hasLoaded: false,
            locale: englishLocale
        )

        #expect(TokenRange.today.localizedHeadingForm(using: localizer) == "Today")
        #expect(TokenRange.today.localizedSentenceForm(using: localizer) == "today")
        #expect(summary.label == "Reading today…")
        #expect(summary.help == "Reading token usage for today.")
        #expect(summary.accessibilityLabel == "Reading token usage for today")
    }

    @Test func billingSummaryExcludesOnlyCacheReads() {
        let usage = tokens(input: 10, output: 20, cacheWrite: 30, cacheRead: 9_999)
        let summary = TokenSummaryPresentation.make(
            perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
            metric: .billingTokens,
            range: .today,
            hasLoaded: true,
            locale: englishLocale
        )

        #expect(summary.value == "60")
        #expect(summary.label == "Billing tokens · Today")
        #expect(summary.numericValue == 60)
        #expect(summary.help.contains("Cache read 9,999"))
    }

    @Test func largeBillingSummaryUsesCompactValueButKeepsExactDisclosure() {
        let usage = tokens(input: 12_345_678_901)
        let summary = TokenSummaryPresentation.make(
            perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
            metric: .billingTokens,
            range: .thirtyDays,
            hasLoaded: true,
            locale: englishLocale
        )

        #expect(summary.value == "12.3B")
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
            pricingDate: Date(timeIntervalSince1970: 1_785_283_200),
            locale: englishLocale
        )

        #expect(summary.value == "$5.00")
        #expect(summary.label == "API equivalent · 7 days")
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
            hasLoaded: true,
            locale: englishLocale
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
            hasLoaded: true,
            locale: englishLocale
        )

        #expect(summary.value == "—")
        #expect(summary.numericValue == nil)
        #expect(summary.help.contains("Codex: codex-auto-review"))
        #expect(summary.accessibilityLabel.contains("unavailable"))
    }

    @Test func unpricedModelListUsesTheEffectiveLocalesListGrammar() {
        let chinese = Locale(identifier: "zh-Hans-CN")
        let summary = TokenSummaryPresentation.make(
            perAgent: [
                agent(.claudeCode, model: "claude-future-model", usage: tokens(output: 10)),
                agent(.codex, model: "codex-future-model", usage: tokens(output: 20)),
            ],
            metric: .apiEquivalent,
            range: .today,
            hasLoaded: true,
            locale: chinese
        )

        #expect(summary.help.contains("Claude Code：claude-future-model和Codex：codex-future-model"))
        #expect(summary.help.contains(", ") == false)
    }

    @Test func pricingReviewDateDoesNotMoveAcrossTimeZones() throws {
        let west = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let east = try #require(TimeZone(identifier: "Pacific/Kiritimati"))

        let westText = TokenSummaryPresentation.reviewedDate(
            locale: englishLocale,
            timeZone: west
        )
        let eastText = TokenSummaryPresentation.reviewedDate(
            locale: englishLocale,
            timeZone: east
        )

        #expect(westText == "Jul 27, 2026")
        #expect(eastText == westText)
    }

    @Test func tokenKindCopyUsesContextSpecificGrammarInEnglishAndChinese() {
        let english = AppLocalizer(locale: englishLocale)
        let chinese = AppLocalizer(locale: Locale(identifier: "zh-Hans-CN"))

        #expect(
            TokenKindPresentation.help(
                for: .directInput,
                isSelected: true,
                using: english
            ) == "Exclude direct input from the selected total"
        )
        #expect(
            TokenKindPresentation.accessibilityLabel(
                for: .directInput,
                using: english
            ) == "Include direct input tokens"
        )
        #expect(
            TokenKindPresentation.selectedRow(
                for: .directInput,
                formattedAmount: "100",
                percentage: "50%",
                using: english
            ) == "Direct input 100 (50% of selected kinds)"
        )
        #expect(
            TokenKindPresentation.help(
                for: .directInput,
                isSelected: true,
                using: chinese
            ) == "从已选合计中排除直接输入"
        )
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
