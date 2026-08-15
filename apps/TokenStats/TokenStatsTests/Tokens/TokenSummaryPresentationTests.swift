//
//  TokenSummaryPresentationTests.swift
//  TokenStatsTests
//
//  Objective Tokens-tab summaries. These use every recorded Token Kind and are
//  deliberately independent from the table's selected-kind projection.
//

import Foundation
import Testing

@MainActor
struct TokenSummaryPresentationTests {
    private let englishLocale = Locale(identifier: "en-US")

    @Test func unloadedSummaryNamesTheRangeBeingRead() {
        let readings = TokenSummaryReadings.make(
            perAgent: [],
            range: .thirtyDays,
            hasLoaded: false,
            locale: englishLocale
        )

        #expect(readings.billing.value == "—")
        #expect(readings.billing.compactValue == nil)
        #expect(readings.billing.label == "Reading 30 days…")
        #expect(readings.billing.numericValue == nil)
        #expect(readings.apiEquivalent.value == "—")
        #expect(readings.apiEquivalent.numericValue == nil)
        #expect(readings.apiEquivalent.help == "Reading estimated API value for 30 days.")
        #expect(
            readings.apiEquivalent.accessibilityLabel
                == "Reading estimated API value for 30 days"
        )
    }

    @Test func currentDayUsesAContextualSentenceFormInsteadOfThePickerTitle() {
        let localizer = AppLocalizer(locale: englishLocale)
        let readings = TokenSummaryReadings.make(
            perAgent: [],
            range: .today,
            hasLoaded: false,
            locale: englishLocale
        )

        #expect(TokenRange.today.localizedHeadingForm(using: localizer) == "Today")
        #expect(TokenRange.today.localizedSentenceForm(using: localizer) == "today")
        #expect(readings.billing.label == "Reading today…")
        #expect(readings.billing.help == "Reading token usage for today.")
        #expect(readings.billing.accessibilityLabel == "Reading token usage for today")
        #expect(readings.apiEquivalent.help == "Reading estimated API value for today.")
        #expect(
            readings.apiEquivalent.accessibilityLabel
                == "Reading estimated API value for today"
        )
    }

    @Test func billingSummaryExcludesOnlyCacheReads() {
        let usage = tokens(input: 10, output: 20, cacheRead: 9_999)
        let summary = TokenSummaryReadings.make(
            perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
            range: .today,
            hasLoaded: true,
            locale: englishLocale
        ).billing

        #expect(summary.value == "30")
        #expect(summary.compactValue == nil)
        #expect(summary.label == "Billing tokens · Today")
        #expect(summary.numericValue == 30)
        #expect(summary.help.contains("Cache read 9,999"))
    }

    @Test func billingSummaryShowsCompactOnlyAtLocaleUnitThresholds() {
        let cases: [(locale: Locale, count: Int, exact: String, compact: String?)] = [
            (Locale(identifier: "en-US"), 999, "999", nil),
            (Locale(identifier: "en-US"), 1_000, "1,000", "1.00K"),
            (Locale(identifier: "zh-Hans-CN"), 9_999, "9,999", nil),
            (Locale(identifier: "zh-Hans-CN"), 10_000, "10,000", "1.00万"),
            (Locale(identifier: "de-DE"), 999_999, "999.999", nil),
            (Locale(identifier: "de-DE"), 1_000_000, "1.000.000", "1,00\u{00A0}Mio."),
            (Locale(identifier: "fr-FR"), 999, "999", nil),
            (Locale(identifier: "fr-FR"), 1_000, "1\u{202F}000", "1,00\u{00A0}k"),
            (Locale(identifier: "ja-JP"), 9_999, "9,999", nil),
            (Locale(identifier: "ja-JP"), 10_000, "10,000", "1.00万"),
            (Locale(identifier: "ru-RU"), 999, "999", nil),
            (Locale(identifier: "ru-RU"), 1_000, "1\u{00A0}000", "1,00\u{00A0}тыс."),
        ]

        for testCase in cases {
            let summary = TokenSummaryReadings.make(
                perAgent: [
                    agent(
                        .claudeCode,
                        model: "claude-opus-5",
                        usage: tokens(input: testCase.count)
                    ),
                ],
                range: .today,
                hasLoaded: true,
                locale: testCase.locale
            ).billing

            #expect(summary.value == testCase.exact)
            #expect(summary.compactValue == testCase.compact)
        }
    }

    @Test func largeBillingSummaryUsesExactHeroAndCompactSecondaryValue() {
        let usage = tokens(input: 52_000_000)
        let summary = TokenSummaryReadings.make(
            perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
            range: .thirtyDays,
            hasLoaded: true,
            locale: englishLocale
        ).billing

        #expect(summary.value == "52,000,000")
        #expect(summary.compactValue == "52.00M")
        #expect(summary.numericValue == 52_000_000)
        #expect(summary.help.contains("52,000,000 billing tokens"))
        #expect(summary.accessibilityLabel.contains("52,000,000"))
    }

    @Test func billingSummaryUsesTwoFractionDigitsAcrossSupportedLanguages() {
        let cases: [(
            locale: Locale,
            count: Int,
            exact: String,
            sharedCompact: String,
            heroCompact: String
        )] = [
            (Locale(identifier: "en-US"), 8_522_266, "8,522,266", "8.5M", "8.52M"),
            (Locale(identifier: "zh-Hans-CN"), 8_522_266, "8,522,266", "852万", "852.23万"),
            (Locale(identifier: "de-DE"), 8_522_266, "8.522.266", "8,5\u{00A0}Mio.", "8,52\u{00A0}Mio."),
            (Locale(identifier: "fr-FR"), 8_522_266, "8\u{202F}522\u{202F}266", "8,5\u{00A0}M", "8,52\u{00A0}M"),
            (Locale(identifier: "ja-JP"), 8_522_266, "8,522,266", "852万", "852.23万"),
            (
                Locale(identifier: "ru-RU"),
                8_522_266,
                "8\u{00A0}522\u{00A0}266",
                "8,5\u{00A0}млн",
                "8,52\u{00A0}млн"
            ),
            (Locale(identifier: "en-US"), 1_250_000_000, "1,250,000,000", "1.2B", "1.25B"),
            (Locale(identifier: "zh-Hans-CN"), 1_250_000_000, "1,250,000,000", "12亿", "12.50亿"),
        ]

        for testCase in cases {
            #expect(
                TokenUsage.compact(testCase.count, locale: testCase.locale)
                    == testCase.sharedCompact
            )
            let usage = tokens(input: testCase.count)
            let summary = TokenSummaryReadings.make(
                perAgent: [agent(.claudeCode, model: "claude-opus-5", usage: usage)],
                range: .thirtyDays,
                hasLoaded: true,
                locale: testCase.locale
            ).billing

            #expect(summary.value == testCase.exact)
            #expect(summary.compactValue == testCase.heroCompact)
            #expect(summary.numericValue == Double(testCase.count))
            #expect(summary.help.contains(testCase.exact))
            #expect(summary.accessibilityLabel.contains(testCase.exact))
        }
    }

    @Test func apiEquivalentUsesTheRecordedAgentAndModel() {
        let usage = tokens(input: 1_000_000)
        let summary = TokenSummaryReadings.make(
            perAgent: [agent(.codex, model: "gpt-5.6-sol", usage: usage)],
            range: .sevenDays,
            hasLoaded: true,
            pricingDate: Date(timeIntervalSince1970: 1_785_283_200),
            locale: englishLocale
        ).apiEquivalent

        #expect(summary.value == "$5.00")
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
        let summary = TokenSummaryReadings.make(
            perAgent: visible,
            range: .today,
            hasLoaded: true,
            locale: englishLocale
        ).billing

        #expect(visible.map(\.id) == [.codex])
        #expect(usage?.billingTokens == codexUsage.billingTokens)
        #expect(summary.value == "50")
    }

    @Test func tokensProjectionExcludesAgentsWithoutUsageInRange() {
        let emptyClaude = TokenOdometerModel.AgentTokens(
            id: .claudeCode,
            label: CodingAgentID.claudeCode.integration.displayName,
            usage: TokenUsage(),
            byModel: []
        )
        let codexUsage = tokens(input: 20, output: 30)
        let codex = agent(.codex, model: "gpt-5.6-sol", usage: codexUsage)

        let visible = TokenAgentProjection.visible(
            [emptyClaude, codex], inOrder: [.claudeCode, .codex]
        )

        #expect(visible.map(\.id) == [.codex])
        #expect(TokenAgentProjection.usage(of: visible) == codexUsage)
    }

    @Test func tokensProjectionKeepsAnAgentWithOnlyCacheReadUsage() {
        let cacheOnly = agent(
            .claudeCode,
            model: "claude-opus-5",
            usage: tokens(cacheRead: 40)
        )

        let visible = TokenAgentProjection.visible(
            [cacheOnly], inOrder: [.claudeCode]
        )

        #expect(visible.map(\.id) == [.claudeCode])
        #expect(visible.first?.usage.billingTokens == 0)
        #expect(visible.first?.usage.totalTokens == 40)
    }

    @Test func unknownModelsStayExplicitlyUnpriced() {
        let usage = tokens(output: 400)
        let summary = TokenSummaryReadings.make(
            perAgent: [agent(.codex, model: "codex-auto-review", usage: usage)],
            range: .today,
            hasLoaded: true,
            locale: englishLocale
        ).apiEquivalent

        #expect(summary.value == "—")
        #expect(summary.numericValue == nil)
        #expect(summary.help.contains("Codex: codex-auto-review"))
        #expect(summary.accessibilityLabel.contains("unavailable"))
        #expect(summary.accessibilityLabel.contains("Unpriced"))
    }

    private func apiEquivalentSummary(
        inputTokens: Int,
        currencyContext: CurrencyDisplayContext
    ) -> TokenApiEquivalentPresentation {
        TokenSummaryReadings.make(
            perAgent: [
                agent(
                    .codex,
                    model: "gpt-5.6-sol",
                    usage: tokens(input: inputTokens)
                ),
            ],
            range: .today,
            hasLoaded: true,
            pricingDate: isoDate("2026-07-31T00:00:00Z"),
            currencyContext: currencyContext,
            locale: englishLocale
        ).apiEquivalent
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
        let summary = TokenSummaryReadings.make(
            perAgent: [
                agent(.claudeCode, model: "claude-future-model", usage: tokens(output: 10)),
                agent(.codex, model: "codex-future-model", usage: tokens(output: 20)),
            ],
            range: .today,
            hasLoaded: true,
            locale: chinese
        ).apiEquivalent

        #expect(summary.help.contains("Claude Code：claude-future-model和Codex：codex-future-model"))
        #expect(summary.help.contains(", ") == false)
    }

    @Test func pricingReviewDateDoesNotMoveAcrossTimeZones() throws {
        let west = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let east = try #require(TimeZone(identifier: "Pacific/Kiritimati"))

        let westText = TokenApiEquivalentPresentation.reviewedDate(
            locale: englishLocale,
            timeZone: west
        )
        let eastText = TokenApiEquivalentPresentation.reviewedDate(
            locale: englishLocale,
            timeZone: east
        )

        #expect(westText == "Aug 4, 2026")
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
        cacheRead: Int = 0
    ) -> TokenUsage {
        TokenUsage(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            responseCount: 1
        )
    }
}
