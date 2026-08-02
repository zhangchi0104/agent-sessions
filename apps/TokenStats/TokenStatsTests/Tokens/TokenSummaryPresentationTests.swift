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

        #expect(summary.value == "12B")
        #expect(summary.numericValue == 12_345_678_901)
        #expect(summary.help.contains("12,345,678,901 billing tokens"))
        #expect(summary.accessibilityLabel.contains("12,345,678,901"))
    }

    @Test func billingSummaryUsesLocaleCompactThresholdsAndKeepsExactDisclosure() {
        let cases: [(locale: Locale, count: Int, compact: String, exact: String)] = [
            (Locale(identifier: "en-US"), 1_250_000, "1.2M", "1,250,000"),
            (Locale(identifier: "zh-Hans-CN"), 1_250_000, "125万", "1,250,000"),
            (Locale(identifier: "en-US"), 1_250_000_000, "1.2B", "1,250,000,000"),
            (Locale(identifier: "zh-Hans-CN"), 1_250_000_000, "12亿", "1,250,000,000"),
            (Locale(identifier: "de-DE"), 1_250_000, "1,2\u{00A0}Mio.", "1.250.000"),
            (Locale(identifier: "fr-FR"), 1_250_000, "1,2\u{00A0}M", "1\u{202F}250\u{202F}000"),
            (Locale(identifier: "ja-JP"), 1_250_000, "125万", "1,250,000"),
            (Locale(identifier: "ru-RU"), 1_250_000, "1,2\u{00A0}млн", "1\u{00A0}250\u{00A0}000"),
        ]

        for testCase in cases {
            let usage = tokens(input: testCase.count)
            let summary = TokenSummaryPresentation.make(
                perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
                metric: .billingTokens,
                range: .thirtyDays,
                hasLoaded: true,
                locale: testCase.locale
            )

            #expect(summary.value == testCase.compact)
            #expect(summary.numericValue == Double(testCase.count))
            #expect(summary.help.contains(testCase.exact))
            #expect(summary.accessibilityLabel.contains(testCase.exact))
        }
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
        #expect(summary.label == "API-equivalent · USD · 7 days")
        #expect(summary.numericValue == 5)
        #expect(summary.help.contains("Original USD estimate $5.00"))
        #expect(summary.help.contains("1 USD = 1 USD"))
    }

    @Test func cnyConversionUsesExactUSDInsteadOfTheRoundedUSDPresentation() {
        let summary = apiEquivalentSummary(
            inputTokens: 1_000,
            currencyContext: context(
                requested: "CNY",
                effective: "CNY",
                rate: Decimal(string: "7.2")!
            )
        )

        // USD is $0.005 before presentation rounding. Converting that exact
        // aggregate yields CNY 0.036 -> 0.04, rather than $0.01 -> CNY 0.08.
        #expect(summary.numericValue == 0.04)
        #expect(summary.label == "API-equivalent · CNY · Today")
        #expect(summary.help.contains("Original USD estimate $0.01"))
        #expect(summary.help.contains("1 USD = 7.2 CNY"))
        #expect(summary.accessibilityLabel.contains("Original USD estimate $0.01"))
    }

    @Test func jpyConversionRoundsUpOnceAtTheTargetMinorUnit() {
        let summary = apiEquivalentSummary(
            inputTokens: 1_000,
            currencyContext: context(
                requested: "JPY",
                effective: "JPY",
                rate: Decimal(string: "150")!
            )
        )

        #expect(summary.numericValue == 1)
        #expect(summary.label == "API-equivalent · JPY · Today")
        #expect(summary.help.contains("1 USD = 150 JPY"))
    }

    @Test func kwdConversionUsesThreeTargetCurrencyFractionDigits() {
        let summary = apiEquivalentSummary(
            inputTokens: 1_000,
            currencyContext: context(
                requested: "KWD",
                effective: "KWD",
                rate: Decimal(string: "0.30715")!
            )
        )

        #expect(summary.numericValue == 0.002)
        #expect(summary.label == "API-equivalent · KWD · Today")
        #expect(summary.help.contains("1 USD = 0.30715 KWD"))
    }

    @Test func unavailableRequestedRateFallsBackToUSDExplicitly() {
        let summary = apiEquivalentSummary(
            inputTokens: 1_000_000,
            currencyContext: context(
                requested: "CNY",
                effective: "USD",
                rate: 1,
                isFallback: true
            )
        )

        #expect(summary.value == "$5.00")
        #expect(summary.numericValue == 5)
        #expect(summary.label == "API-equivalent · USD fallback · Today")
        #expect(summary.help.contains("No usable CNY exchange rate"))
        #expect(summary.help.contains("No FX conversion was applied"))
        #expect(!summary.help.contains("Exchange rate: 1 USD = 1 USD"))
        #expect(!summary.help.contains("Rate status: current"))
        #expect(summary.accessibilityLabel.contains("showing the original USD estimate"))
    }

    @Test func staleRateDisclosesRateDateFetchTimeAndStatus() {
        let summary = apiEquivalentSummary(
            inputTokens: 1_000_000,
            currencyContext: context(
                requested: "CNY",
                effective: "CNY",
                rate: Decimal(string: "7.2")!,
                rateDate: isoDate("2026-07-31T00:00:00Z"),
                fetchedAt: isoDate("2026-08-01T08:30:00Z"),
                isStale: true
            )
        )

        #expect(summary.help.contains("Rate date: Jul 31, 2026"))
        #expect(summary.help.contains("Fetched: Aug 1, 2026"))
        #expect(summary.help.contains("Rate status: stale cached rate"))
        #expect(summary.label == "API-equivalent · CNY stale · Today")
        #expect(summary.accessibilityLabel.contains("Rate date: Jul 31, 2026"))
        #expect(summary.accessibilityLabel.contains("stale cached rate"))
    }

    @Test func transitionIdentityChangesAcrossUnitsButNotAcrossRatesForOneCurrency() {
        let firstCNY = apiEquivalentSummary(
            inputTokens: 1_000,
            currencyContext: context(
                requested: "CNY",
                effective: "CNY",
                rate: Decimal(string: "7.1")!
            )
        )
        let updatedCNY = apiEquivalentSummary(
            inputTokens: 2_000,
            currencyContext: context(
                requested: "CNY",
                effective: "CNY",
                rate: Decimal(string: "7.2")!
            )
        )
        let jpy = apiEquivalentSummary(
            inputTokens: 1_000,
            currencyContext: context(
                requested: "JPY",
                effective: "JPY",
                rate: 150
            )
        )

        #expect(firstCNY.transitionIdentity == updatedCNY.transitionIdentity)
        #expect(firstCNY.transitionIdentity != jpy.transitionIdentity)
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
        #expect(summary.accessibilityLabel.contains("Unpriced"))
    }

    private func apiEquivalentSummary(
        inputTokens: Int,
        currencyContext: CurrencyDisplayContext
    ) -> TokenSummaryPresentation {
        TokenSummaryPresentation.make(
            perAgent: [
                agent(
                    .codex,
                    model: "gpt-5.6-sol",
                    usage: tokens(input: inputTokens)
                ),
            ],
            metric: .apiEquivalent,
            range: .today,
            hasLoaded: true,
            pricingDate: isoDate("2026-07-31T00:00:00Z"),
            currencyContext: currencyContext,
            locale: englishLocale
        )
    }

    private func context(
        requested: String,
        effective: String,
        rate: Decimal,
        rateDate: Date? = nil,
        fetchedAt: Date? = nil,
        isStale: Bool = false,
        isFallback: Bool = false
    ) -> CurrencyDisplayContext {
        CurrencyDisplayContext(
            requestedCode: CurrencyCode(requested)!,
            currencyCode: CurrencyCode(effective)!,
            rate: rate,
            rateDate: rateDate,
            fetchedAt: fetchedAt,
            isStale: isStale,
            isFallback: isFallback,
            localeIdentifier: "en_US_POSIX"
        )
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
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

    @Test func tokenKindCopyUsesContextSpecificGrammarInEverySupportedLanguage() {
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

        let addedLanguageCases:
            [(
                locale: String,
                help: String,
                accessibility: String,
                selectedRow: String
            )] = [
                (
                    "de-DE",
                    "Token aus direkten Eingaben aus der ausgewählten Summe ausschließen",
                    "Token aus direkten Eingaben einbeziehen",
                    "Direkte Eingabe 100 (50% der ausgewählten Typen)"
                ),
                (
                    "fr-FR",
                    "Exclure les tokens du type « entrée directe » du total sélectionné",
                    "Inclure les tokens du type « entrée directe »",
                    "Entrée directe 100 (50% du total sélectionné)"
                ),
                (
                    "ja-JP",
                    "選択合計からトークン種別「直接入力」を除外",
                    "トークン種別「直接入力」を含める",
                    "直接入力：100（選択した種別に占める割合：50%）"
                ),
                (
                    "ru-RU",
                    "Не учитывать прямой ввод в итоге по выбранным типам",
                    "Учитывать токены типа «прямой ввод»",
                    "Прямой ввод: 100 (50% от итога по выбранным типам)"
                ),
            ]

        for testCase in addedLanguageCases {
            let localizer = AppLocalizer(locale: Locale(identifier: testCase.locale))
            #expect(
                TokenKindPresentation.help(
                    for: .directInput,
                    isSelected: true,
                    using: localizer
                ) == testCase.help
            )
            #expect(
                TokenKindPresentation.accessibilityLabel(
                    for: .directInput,
                    using: localizer
                ) == testCase.accessibility
            )
            #expect(
                TokenKindPresentation.selectedRow(
                    for: .directInput,
                    formattedAmount: "100",
                    percentage: "50%",
                    using: localizer
                ) == testCase.selectedRow
            )
        }
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
