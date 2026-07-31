//
//  TokenSelectionTests.swift
//  TokenStatsTests
//
//  The Token Kind headings are a display projection over the raw four-kind
//  Odometer. They may change selected subtotals and percentages, but never the
//  objective raw or Billing-token readings.
//

import Testing
@testable import TokenStats

struct TokenSelectionTests {
    private let usage = TokenUsage(
        inputTokens: 10,
        outputTokens: 20,
        cacheCreationTokens: 30,
        cacheReadTokens: 40,
        responseCount: 1
    )

    @Test func selectedTotalIncludesOnlyEnabledKinds() {
        #expect(usage.selectedTotal([.directInput, .cacheRead]) == 50)
        #expect(usage.selectedTotal(Set(TokenKind.allCases)) == 100)
        #expect(usage.selectedTotal([]) == 0)
    }

    @Test func filteringDoesNotChangeObjectiveTotals() {
        _ = usage.selectedTotal([.directInput])

        #expect(usage.totalTokens == 100)
        #expect(usage.billingTokens == 60)
    }

    @Test func enabledKindsSupportAllThreeValueFormats() {
        #expect(
            TokenValueFormatting.cell(
                amount: 10,
                selectedTotal: 30,
                isSelected: true,
                mode: .value
            ) == "10"
        )
        #expect(
            TokenValueFormatting.cell(
                amount: 10,
                selectedTotal: 30,
                isSelected: true,
                mode: .percentage
            ) == "33.3%"
        )
        #expect(
            TokenValueFormatting.cell(
                amount: 10,
                selectedTotal: 30,
                isSelected: true,
                mode: .valueAndPercentage
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
                    mode: mode
                ) == "40"
            )
        }
        #expect(
            TokenValueFormatting.cell(
                amount: 0,
                selectedTotal: 60,
                isSelected: true,
                mode: .percentage
            ) == "–"
        )
    }
}
