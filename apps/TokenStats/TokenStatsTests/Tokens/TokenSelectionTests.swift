//
//  TokenSelectionTests.swift
//  TokenStatsTests
//
//  The Token Kind headings are a display projection over the raw three-kind
//  Odometer. They may change selected subtotals and percentages, but never the
//  objective raw or Billing-token readings.
//

import Foundation
import Testing

struct TokenSelectionTests {
    private let englishLocale = Locale(identifier: "en-US")

    private let usage = TokenUsage(
        inputTokens: 10,
        outputTokens: 20,
        cacheReadTokens: 40,
        responseCount: 1
    )

    @Test func selectedTotalIncludesOnlyEnabledKinds() {
        #expect(usage.selectedTotal([.directInput, .cacheRead]) == 50)
        #expect(usage.selectedTotal(Set(TokenKind.allCases)) == 70)
        #expect(usage.selectedTotal([]) == 0)
    }

    @Test func filteringDoesNotChangeObjectiveTotals() {
        _ = usage.selectedTotal([.directInput])

        #expect(usage.totalTokens == 70)
        #expect(usage.billingTokens == 30)
    }

    @Test func enabledKindsSupportAllThreeValueFormats() {
        #expect(
            TokenValueFormatting.cell(
                amount: 10,
                selectedTotal: 30,
                isSelected: true,
                mode: .value,
                locale: englishLocale
            ) == "10"
        )
        #expect(
            TokenValueFormatting.cell(
                amount: 10,
                selectedTotal: 30,
                isSelected: true,
                mode: .percentage,
                locale: englishLocale
            ) == "33.3%"
        )
        #expect(
            TokenValueFormatting.cell(
                amount: 10,
                selectedTotal: 30,
                isSelected: true,
                mode: .valueAndPercentage,
                locale: englishLocale
            ) == "10\n(33.3%)"
        )
    }

    @Test func disabledKindsKeepOnlyTheirDimmedRawValue() {
        for mode in TokenValueDisplayMode.allCases {
            #expect(
                TokenValueFormatting.cell(
                    amount: 40,
                    selectedTotal: 60,
                    isSelected: false,
                    mode: mode,
                    locale: englishLocale
                ) == "40"
            )
        }
        #expect(
            TokenValueFormatting.cell(
                amount: 0,
                selectedTotal: 60,
                isSelected: true,
                mode: .percentage,
                locale: englishLocale
            ) == "–"
        )
    }

    @Test func tokenCellsUseTheSameLocaleCompactNotationAsTotals() {
        let cases = [
            (locale: Locale(identifier: "en-US"), expected: "1.2M\n(50%)"),
            (locale: Locale(identifier: "zh-Hans-CN"), expected: "125万\n(50%)"),
        ]

        for testCase in cases {
            #expect(
                TokenValueFormatting.cell(
                    amount: 1_250_000,
                    selectedTotal: 2_500_000,
                    isSelected: true,
                    mode: .valueAndPercentage,
                    locale: testCase.locale
                ) == testCase.expected
            )
        }
    }
}
