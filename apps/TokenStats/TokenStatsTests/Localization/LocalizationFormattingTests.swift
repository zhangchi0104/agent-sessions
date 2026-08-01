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
