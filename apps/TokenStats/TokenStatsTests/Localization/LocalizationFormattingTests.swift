//
//  LocalizationFormattingTests.swift
//  TokenStatsTests
//
//  Copy follows TokenStats' selected language; formatting follows the system
//  region. Currency is deliberately USD-only until a separate currency-choice
//  feature is designed.
//

import Foundation
import Testing
@testable import TokenStats

@MainActor
struct LocalizationFormattingTests {
    private struct LocaleFixture {
        let identifier: String
        let percent: String
        let duration: String
        let compactTokens: String
        let usd: String
    }

    private struct CompactLocaleFixture {
        let identifier: String
        let expectations: [(count: Int, value: String)]
    }

    private let fixtures = [
        LocaleFixture(
            identifier: "en-US",
            percent: "29%",
            duration: "1d 3h",
            compactTokens: "1.2M",
            usd: "$5.01"
        ),
        LocaleFixture(
            identifier: "en-DE",
            percent: "29\u{00A0}%",
            duration: "1d 3h",
            compactTokens: "1,2M",
            usd: "5,01\u{00A0}US$"
        ),
        LocaleFixture(
            identifier: "zh-Hans-US",
            percent: "29%",
            duration: "1天3小时",
            compactTokens: "125万",
            usd: "$5.01"
        ),
        LocaleFixture(
            identifier: "zh-Hans-CN",
            percent: "29%",
            duration: "1天3小时",
            compactTokens: "125万",
            usd: "US$5.01"
        ),
        LocaleFixture(
            identifier: "de-US",
            percent: "29\u{00A0}%",
            duration: "1d 3h",
            compactTokens: "1.2\u{00A0}Mio.",
            usd: "5.01\u{00A0}$"
        ),
        LocaleFixture(
            identifier: "de-DE",
            percent: "29\u{00A0}%",
            duration: "1d 3h",
            compactTokens: "1,2\u{00A0}Mio.",
            usd: "5,01\u{00A0}$"
        ),
        LocaleFixture(
            identifier: "fr-US",
            percent: "29\u{00A0}%",
            duration: "1j 3h",
            compactTokens: "1.2\u{00A0}M",
            usd: "5.01\u{00A0}$"
        ),
        LocaleFixture(
            identifier: "fr-FR",
            percent: "29\u{00A0}%",
            duration: "1j 3h",
            compactTokens: "1,2\u{00A0}M",
            usd: "5,01\u{00A0}$US"
        ),
        LocaleFixture(
            identifier: "ja-US",
            percent: "29%",
            duration: "1日3時間",
            compactTokens: "125万",
            usd: "$5.01"
        ),
        LocaleFixture(
            identifier: "ja-JP",
            percent: "29%",
            duration: "1日3時間",
            compactTokens: "125万",
            usd: "$5.01"
        ),
        LocaleFixture(
            identifier: "ru-US",
            percent: "29\u{00A0}%",
            duration: "1 д. 3 ч",
            compactTokens: "1.2\u{00A0}млн",
            usd: "5.01\u{00A0}$"
        ),
        LocaleFixture(
            identifier: "ru-RU",
            percent: "29\u{00A0}%",
            duration: "1 д. 3 ч",
            compactTokens: "1,2\u{00A0}млн",
            usd: "5,01\u{00A0}$"
        ),
    ]

    private let compactFixtures: [CompactLocaleFixture] = [
        CompactLocaleFixture(
            identifier: "en-US",
            expectations: [
                (999, "999"),
                (1_000, "1K"),
                (12_345, "12K"),
                (1_250_000, "1.2M"),
                (100_000_000, "100M"),
                (1_250_000_000, "1.2B"),
                (12_345_678_901, "12B"),
            ]
        ),
        CompactLocaleFixture(
            identifier: "en-DE",
            expectations: [
                (1_250_000, "1,2M"),
                (1_250_000_000, "1,2B"),
            ]
        ),
        CompactLocaleFixture(
            identifier: "zh-Hans-US",
            expectations: Self.chineseCompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "zh-Hans-CN",
            expectations: Self.chineseCompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "de-US",
            expectations: Self.germanUSCompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "de-DE",
            expectations: Self.germanDECompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "fr-US",
            expectations: Self.frenchUSCompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "fr-FR",
            expectations: Self.frenchFRCompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "ja-US",
            expectations: Self.japaneseCompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "ja-JP",
            expectations: Self.japaneseCompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "ru-US",
            expectations: Self.russianUSCompactExpectations
        ),
        CompactLocaleFixture(
            identifier: "ru-RU",
            expectations: Self.russianRUCompactExpectations
        ),
    ]

    private static let chineseCompactExpectations: [(count: Int, value: String)] = [
        (1_000, "1000"),
        (9_999, "9999"),
        (10_000, "1万"),
        (12_345, "1.2万"),
        (1_250_000, "125万"),
        (100_000_000, "1亿"),
        (1_250_000_000, "12亿"),
        (12_345_678_901, "123亿"),
    ]

    private static let germanUSCompactExpectations: [(count: Int, value: String)] = [
        (1_000, "1000"),
        (12_345, "12,345"),
        (1_250_000, "1.2\u{00A0}Mio."),
        (100_000_000, "100\u{00A0}Mio."),
        (1_250_000_000, "1.2\u{00A0}Mrd."),
        (12_345_678_901, "12\u{00A0}Mrd."),
    ]

    private static let germanDECompactExpectations: [(count: Int, value: String)] = [
        (1_000, "1000"),
        (12_345, "12.345"),
        (1_250_000, "1,2\u{00A0}Mio."),
        (100_000_000, "100\u{00A0}Mio."),
        (1_250_000_000, "1,2\u{00A0}Mrd."),
        (12_345_678_901, "12\u{00A0}Mrd."),
    ]

    private static let frenchUSCompactExpectations: [(count: Int, value: String)] = [
        (1_000, "1\u{00A0}k"),
        (12_345, "12\u{00A0}k"),
        (1_250_000, "1.2\u{00A0}M"),
        (100_000_000, "100\u{00A0}M"),
        (1_250_000_000, "1.2\u{00A0}Md"),
        (12_345_678_901, "12\u{00A0}Md"),
    ]

    private static let frenchFRCompactExpectations: [(count: Int, value: String)] = [
        (1_000, "1\u{00A0}k"),
        (12_345, "12\u{00A0}k"),
        (1_250_000, "1,2\u{00A0}M"),
        (100_000_000, "100\u{00A0}M"),
        (1_250_000_000, "1,2\u{00A0}Md"),
        (12_345_678_901, "12\u{00A0}Md"),
    ]

    private static let japaneseCompactExpectations: [(count: Int, value: String)] = [
        (1_000, "1000"),
        (9_999, "9999"),
        (10_000, "1万"),
        (12_345, "1.2万"),
        (1_250_000, "125万"),
        (100_000_000, "1億"),
        (1_250_000_000, "12億"),
        (12_345_678_901, "123億"),
    ]

    private static let russianUSCompactExpectations: [(count: Int, value: String)] = [
        (1_000, "1\u{00A0}тыс."),
        (12_345, "12\u{00A0}тыс."),
        (1_250_000, "1.2\u{00A0}млн"),
        (100_000_000, "100\u{00A0}млн"),
        (1_250_000_000, "1.2\u{00A0}млрд"),
        (12_345_678_901, "12\u{00A0}млрд"),
    ]

    private static let russianRUCompactExpectations: [(count: Int, value: String)] = [
        (1_000, "1\u{00A0}тыс."),
        (12_345, "12\u{00A0}тыс."),
        (1_250_000, "1,2\u{00A0}млн"),
        (100_000_000, "100\u{00A0}млн"),
        (1_250_000_000, "1,2\u{00A0}млрд"),
        (12_345_678_901, "12\u{00A0}млрд"),
    ]

    @Test func percentagesFloorBeforeLocaleFormatting() {
        for fixture in fixtures {
            let locale = Locale(identifier: fixture.identifier)
            #expect(
                UsageFormatting.remainingPercentText(29.999, locale: locale) == fixture.percent,
                "Unexpected floored percentage for \(fixture.identifier)"
            )
            #expect(UsageFormatting.remainingPercentText(99.999, locale: locale).contains("100") == false)
            #expect(UsageFormatting.remainingPercentText(100.9, locale: locale).contains("100"))
        }
    }

    @Test func durationAndCompactTokenUnitsFollowLanguageWhileSeparatorsFollowRegion() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetAt = now.addingTimeInterval((27 * 60 * 60) + (12 * 60))

        for fixture in fixtures {
            let locale = Locale(identifier: fixture.identifier)
            let duration = try #require(
                UsageFormatting.compactDuration(to: resetAt, now: now, locale: locale)
            )
            #expect(duration == fixture.duration, "Unexpected duration for \(fixture.identifier)")
            #expect(
                TokenUsage.compact(1_250_000, locale: locale) == fixture.compactTokens,
                "Unexpected compact Token count for \(fixture.identifier)"
            )
        }
    }

    @Test func compactTokensUseLanguageAndRegionalPatternsAtNativeThresholds() {
        for fixture in compactFixtures {
            let locale = Locale(identifier: fixture.identifier)
            for expectation in fixture.expectations {
                #expect(
                    TokenUsage.compact(expectation.count, locale: locale) == expectation.value,
                    "Unexpected compact value for \(expectation.count) in \(fixture.identifier)"
                )
            }
        }
    }

    @Test func regionalEnglishCompactVariantsDelegateToFoundation() {
        let counts = [1_000, 12_345, 1_250_000, 100_000_000, 1_250_000_000]

        // Exact compact spellings are CLDR data and can change between macOS
        // releases. Compare against the current runtime so en-GB and en-IN
        // retain their regional conventions without freezing one CLDR version.
        for identifier in ["en-GB", "en-IN"] {
            let locale = Locale(identifier: identifier)
            for count in counts {
                let foundationValue = count.formatted(
                    .number
                        .notation(.compactName)
                        .locale(locale)
                )
                #expect(
                    TokenUsage.compact(count, locale: locale) == foundationValue,
                    "Unexpected Foundation compact value for \(count) in \(identifier)"
                )
            }
        }
    }

    @Test func tableHeadingKeepsExactCountForHelpAndAccessibility() {
        let cases = [
            (
                locale: Locale(identifier: "en-US"),
                visual: "RANGE_SENTINEL · 1.2M selected",
                exact: "RANGE_SENTINEL · 1,250,000 selected"
            ),
            (
                locale: Locale(identifier: "zh-Hans-CN"),
                visual: "RANGE_SENTINEL · 已选合计 125万",
                exact: "RANGE_SENTINEL · 已选合计 1,250,000"
            ),
            (
                locale: Locale(identifier: "de-DE"),
                visual: "RANGE_SENTINEL · 1,2\u{00A0}Mio. ausgewählt",
                exact: "RANGE_SENTINEL · 1.250.000 ausgewählt"
            ),
            (
                locale: Locale(identifier: "fr-FR"),
                visual: "RANGE_SENTINEL · Total sélectionné : 1,2\u{00A0}M",
                exact: "RANGE_SENTINEL · Total sélectionné : 1\u{202F}250\u{202F}000"
            ),
            (
                locale: Locale(identifier: "ja-JP"),
                visual: "RANGE_SENTINEL · 選択合計 125万",
                exact: "RANGE_SENTINEL · 選択合計 1,250,000"
            ),
            (
                locale: Locale(identifier: "ru-RU"),
                visual: "RANGE_SENTINEL · выбрано 1,2\u{00A0}млн",
                exact: "RANGE_SENTINEL · выбрано 1\u{00A0}250\u{00A0}000"
            ),
        ]

        for testCase in cases {
            let presentation = TokenTableHeadingPresentation.make(
                rangeHeading: "RANGE_SENTINEL",
                selectedTotal: 1_250_000,
                localizer: AppLocalizer(locale: testCase.locale)
            )
            #expect(presentation.visual == testCase.visual)
            #expect(presentation.help == testCase.exact)
            #expect(presentation.accessibilityLabel == testCase.exact)
        }

        let empty = TokenTableHeadingPresentation.make(
            rangeHeading: "RANGE_SENTINEL",
            selectedTotal: nil,
            localizer: AppLocalizer(locale: Locale(identifier: "en-US"))
        )
        #expect(empty.visual == "RANGE_SENTINEL")
        #expect(empty.help == "RANGE_SENTINEL")
        #expect(empty.accessibilityLabel == "RANGE_SENTINEL")
    }

    @Test func remainingDurationsNeverRoundUpHiddenLowerUnits() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cases = [
            (seconds: 3_599.0, englishCompact: "59m", englishSpoken: "resets in 59 minutes",
             chineseCompact: "59分钟", chineseSpoken: "59分钟后重置"),
            (seconds: 119.0, englishCompact: "1m", englishSpoken: "resets in 1 minute",
             chineseCompact: "1分钟", chineseSpoken: "1分钟后重置"),
            (seconds: 100_799.0, englishCompact: "1d 3h", englishSpoken: "resets in 1 day, 3 hours",
             chineseCompact: "1天3小时", chineseSpoken: "1天3小时后重置"),
        ]

        for testCase in cases {
            let resetAt = now.addingTimeInterval(testCase.seconds)
            let english = AppLocalizer(locale: Locale(identifier: "en-US"))
            let chinese = AppLocalizer(locale: Locale(identifier: "zh-Hans-CN"))

            #expect(
                try #require(
                    UsageFormatting.compactDuration(to: resetAt, now: now, locale: english.locale)
                ) == testCase.englishCompact
            )
            #expect(
                UsageFormatting.resetCountdown(to: resetAt, now: now, localizer: english)
                    == testCase.englishSpoken
            )
            #expect(
                try #require(
                    UsageFormatting.compactDuration(to: resetAt, now: now, locale: chinese.locale)
                ) == testCase.chineseCompact
            )
            #expect(
                UsageFormatting.resetCountdown(to: resetAt, now: now, localizer: chinese)
                    == testCase.chineseSpoken
            )
        }
    }

    @Test func apiCostRoundsUpToCentsAndRemainsUSDInEveryRegion() {
        let estimate = ApiCostEstimate(
            costUSD: Decimal(string: "5.001")!,
            pricedTokens: 1,
            unpricedTokens: 0,
            unpricedModels: []
        )
        #expect(estimate.roundedCostUSD == Decimal(string: "5.01"))

        for fixture in fixtures {
            let value = estimate.formattedCost(locale: Locale(identifier: fixture.identifier))
            #expect(value == fixture.usd, "Unexpected USD spelling for \(fixture.identifier)")
            #expect(value.contains("€") == false)
            #expect(value.contains("¥") == false)
        }
    }

    @Test func accessibilitySentenceKeepsCompleteArgumentsInSemanticOrder() throws {
        let english = GaugeContent(
            identity: .weekly,
            title: "TITLE_SENTINEL",
            subtitle: .text("RESET_SENTINEL"),
            percentRemaining: 37,
            progress: 0.37,
            centerText: "37%",
            localizer: AppLocalizer(locale: Locale(identifier: "en-US"))
        ).spokenLabel
        let chinese = GaugeContent(
            identity: .weekly,
            title: "TITLE_SENTINEL",
            subtitle: .text("RESET_SENTINEL"),
            percentRemaining: 37,
            progress: 0.37,
            centerText: "37%",
            localizer: AppLocalizer(locale: Locale(identifier: "zh-Hans-CN"))
        ).spokenLabel

        #expect(english == "TITLE_SENTINEL, 37% left, RESET_SENTINEL")
        #expect(chinese != english)
        for sentence in [english, chinese] {
            #expect(sentence.contains("usage.gauge.accessibility") == false)
            try expectOrderedOnce(
                ["TITLE_SENTINEL", "37%", "RESET_SENTINEL"],
                in: sentence
            )
        }
    }

    @Test func tokenCountSentencesUseCatalogPluralRules() {
        let english = AppLocalizer(locale: Locale(identifier: "en-US"))

        #expect(
            english.localized(
                LocalizedStringResource.tokensAgentSelectedTotalHelp(1, "1")
            ) == "1 selected token of 1 total across all four kinds"
        )
        #expect(
            english.localized(
                LocalizedStringResource.tokensAgentSelectedTotalHelp(2, "2")
            ) == "2 selected tokens of 2 total across all four kinds"
        )
        #expect(
            english.localized(
                LocalizedStringResource.tokensSummaryBillingAccessibility(1, "Today")
            ) == "1 billing token for Today; cache reads excluded"
        )
        #expect(
            english.localized(
                LocalizedStringResource.tokensSummaryBillingAccessibility(2, "Today")
            ) == "2 billing tokens for Today; cache reads excluded"
        )
    }

    @Test func addedLanguagesUseTheirCatalogPluralCategoriesAtRuntime() {
        let fixtures: [(locale: String, count: Int, expected: String)] = [
            (
                "ru-RU",
                1,
                "Выбран 1 токен; всего по всем четырём типам: TOTAL"
            ),
            (
                "ru-RU",
                2,
                "Выбрано 2 токена; всего по всем четырём типам: TOTAL"
            ),
            (
                "ru-RU",
                5,
                "Выбрано 5 токенов; всего по всем четырём типам: TOTAL"
            ),
            (
                "ru-RU",
                21,
                "Выбран 21 токен; всего по всем четырём типам: TOTAL"
            ),
            (
                "ru-RU",
                22,
                "Выбрано 22 токена; всего по всем четырём типам: TOTAL"
            ),
            (
                "ru-RU",
                25,
                "Выбрано 25 токенов; всего по всем четырём типам: TOTAL"
            ),
            (
                "de-DE",
                1,
                "1 ausgewähltes Token von insgesamt TOTAL über alle vier Typen"
            ),
            (
                "de-DE",
                2,
                "2 ausgewählte Token von insgesamt TOTAL über alle vier Typen"
            ),
            (
                "ja-JP",
                1,
                "選択合計は1トークンです（4種類すべての合計：TOTAL）"
            ),
            (
                "ja-JP",
                2,
                "選択合計は2トークンです（4種類すべての合計：TOTAL）"
            ),
            (
                "fr-FR",
                0,
                "0 token sélectionné sur un total de TOTAL pour les quatre types"
            ),
            (
                "fr-FR",
                1,
                "1 token sélectionné sur un total de TOTAL pour les quatre types"
            ),
            (
                "fr-FR",
                2,
                "2 tokens sélectionnés sur un total de TOTAL pour les quatre types"
            ),
            (
                "fr-FR",
                1_000_000,
                "1\u{202F}000\u{202F}000 tokens sélectionnés sur un total de TOTAL pour les quatre types"
            ),
        ]

        for fixture in fixtures {
            let localizer = AppLocalizer(locale: Locale(identifier: fixture.locale))
            #expect(
                localizer.localized(
                    LocalizedStringResource.tokensAgentSelectedTotalHelp(
                        fixture.count,
                        "TOTAL"
                    )
                ) == fixture.expected,
                "Unexpected plural branch for \(fixture.count) in \(fixture.locale)"
            )
        }
    }

    @Test func appOwnedFallbacksAndErrorPrefixesFollowTheEffectiveLanguage() {
        let english = AppLocalizer(locale: Locale(identifier: "en-US"))
        let chinese = AppLocalizer(locale: Locale(identifier: "zh-Hans-CN"))

        #expect(ModelName.unattributed.localizedDisplayName(using: english) == "Unknown")
        #expect(ModelName.unattributed.localizedDisplayName(using: chinese) == "未知")
        #expect(ModelName.named("unknown").localizedDisplayName(using: chinese) == "unknown")

        let fallback = ApiUnpricedModel.model(agent: .codex, model: .unattributed)
        #expect(fallback.localizedDescription(using: english) == "Codex: Unknown")
        #expect(fallback.localizedDescription(using: chinese) == "Codex：未知")
        #expect(
            UsageError.noWindows(body: "RAW_BODY").displayText(using: chinese)
                == "已收到数据，但未识别出用量周期。RAW_BODY"
        )
    }

    private func expectOrderedOnce(_ values: [String], in sentence: String) throws {
        var priorEnd = sentence.startIndex
        for value in values {
            let range = try #require(sentence.range(of: value, range: priorEnd..<sentence.endIndex))
            #expect(sentence[range.upperBound...].contains(value) == false)
            priorEnd = range.upperBound
        }
    }
}
