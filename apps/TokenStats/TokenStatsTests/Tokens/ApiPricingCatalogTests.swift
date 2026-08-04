//
//  ApiPricingCatalogTests.swift
//  TokenStatsTests
//
//  Locks the macOS API-equivalent pricing domain to the Windows catalog.
//

import Foundation
import Testing

struct ApiPricingCatalogTests {
    private let reviewed = ApiPricingDate(year: 2026, month: 8, day: 4)

    @Test func metadataMatchesTheWindowsCatalog() {
        #expect(ApiPricingCatalog.lastReviewed == reviewed)
        #expect(
            ApiPricingCatalog.openAIPricingSource ==
                "https://developers.openai.com/api/docs/pricing"
        )
        #expect(
            ApiPricingCatalog.anthropicPricingSource ==
                "https://platform.claude.com/docs/en/about-claude/pricing"
        )
    }

    @Test func everyWindowsPriceRuleResolvesToTheSameRates() throws {
        let cases: [(ApiPricingAgent, String, ApiTokenRates)] = [
            (.codex, "gpt-5.6-sol", openAI("5", "6.25", "0.50", "30")),
            (.codex, "gpt-5.6-terra", openAI("2", "2.50", "0.20", "12")),
            (.codex, "gpt-5.6-luna", openAI("0.20", "0.25", "0.02", "1.20")),
            (.codex, "gpt-5.6", openAI("5", "6.25", "0.50", "30")),
            (.codex, "gpt-5.5", openAI("5", "0", "0.50", "30")),
            (.codex, "gpt-5.4", openAI("2.50", "0", "0.25", "15")),
            (.codex, "gpt-5.3-codex", openAI("1.75", "1.75", "0.175", "14")),
            (.codex, "gpt-5.2-codex", openAI("1.75", "1.75", "0.175", "14")),
            (.codex, "gpt-5.2", openAI("1.75", "1.75", "0.175", "14")),
            (.codex, "gpt-5.1-codex-mini", openAI("0.25", "0.25", "0.025", "2")),
            (.codex, "gpt-5.1-codex-max", openAI("1.25", "1.25", "0.125", "10")),
            (.codex, "gpt-5.1-codex", openAI("1.25", "1.25", "0.125", "10")),
            (.codex, "gpt-5.1", openAI("1.25", "1.25", "0.125", "10")),
            (.codex, "gpt-5-codex", openAI("1.25", "1.25", "0.125", "10")),
            (.codex, "gpt-5", openAI("1.25", "1.25", "0.125", "10")),
            (.codex, "codex-mini-latest", openAI("1.50", "1.50", "0.375", "6")),

            (.claudeCode, "claude-fable-5", anthropic("10", "12.50", "20", "1", "50")),
            (.claudeCode, "claude-mythos-5", anthropic("10", "12.50", "20", "1", "50")),
            (.claudeCode, "claude-opus-5", anthropic("5", "6.25", "10", "0.50", "25")),
            (.claudeCode, "claude-opus-4-8", anthropic("5", "6.25", "10", "0.50", "25")),
            (.claudeCode, "claude-opus-4-7", anthropic("5", "6.25", "10", "0.50", "25")),
            (.claudeCode, "claude-opus-4-6", anthropic("5", "6.25", "10", "0.50", "25")),
            (.claudeCode, "claude-opus-4-5", anthropic("5", "6.25", "10", "0.50", "25")),
            (.claudeCode, "claude-opus-4-1", anthropic("15", "18.75", "30", "1.50", "75")),
            (.claudeCode, "claude-opus-4", anthropic("15", "18.75", "30", "1.50", "75")),
            (.claudeCode, "claude-sonnet-4-6", anthropic("3", "3.75", "6", "0.30", "15")),
            (.claudeCode, "claude-sonnet-4-5", anthropic("3", "3.75", "6", "0.30", "15")),
            (.claudeCode, "claude-sonnet-4", anthropic("3", "3.75", "6", "0.30", "15")),
            (.claudeCode, "claude-3-7-sonnet", anthropic("3", "3.75", "6", "0.30", "15")),
            (.claudeCode, "claude-3-5-sonnet", anthropic("3", "3.75", "6", "0.30", "15")),
            (.claudeCode, "claude-haiku-4-5", anthropic("1", "1.25", "2", "0.10", "5")),
            (.claudeCode, "claude-3-5-haiku", anthropic("0.80", "1", "1.60", "0.08", "4")),
            (.claudeCode, "claude-3-haiku", anthropic("0.25", "0.3125", "0.50", "0.025", "1.25")),
            (.claudeCode, "claude-3-opus", anthropic("15", "18.75", "30", "1.50", "75")),
        ]

        for (agent, model, expected) in cases {
            let resolved = try #require(
                ApiPricingCatalog.rates(
                    for: agent,
                    model: model,
                    pricingDate: reviewed
                )
            )
            #expect(resolved == expected, "Unexpected rates for \(model)")
        }
    }

    @Test func sonnetFiveSwitchesPriceOnTheWindowsBoundary() throws {
        let introductory = try #require(
            ApiPricingCatalog.rates(
                for: .claudeCode,
                model: "claude-sonnet-5",
                pricingDate: ApiPricingDate(year: 2026, month: 8, day: 31)
            )
        )
        let standard = try #require(
            ApiPricingCatalog.rates(
                for: .claudeCode,
                model: "claude-sonnet-5",
                pricingDate: ApiPricingDate(year: 2026, month: 9, day: 1)
            )
        )

        #expect(introductory == anthropic("2", "2.50", "4", "0.20", "10"))
        #expect(standard == anthropic("3", "3.75", "6", "0.30", "15"))
    }

    @Test func onlyDatedSnapshotsExtendAKnownModelPrefix() {
        #expect(
            ApiPricingCatalog.rates(
                for: .codex,
                model: "GPT-5.6-SOL-2026-07-27",
                pricingDate: reviewed
            ) == openAI("5", "6.25", "0.50", "30")
        )
        #expect(
            ApiPricingCatalog.rates(
                for: .codex,
                model: "gpt-5.6-sol-spark",
                pricingDate: reviewed
            ) == nil
        )
        #expect(
            ApiPricingCatalog.rates(
                for: .claudeCode,
                model: "gpt-5.6-sol",
                pricingDate: reviewed
            ) == nil
        )
    }

    @Test func estimateUsesAllFourKindsAndTheDefaultCacheWriteRate() {
        let codex = usage(
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheRead: 1_000_000
        )
        let claude = usage(
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheRead: 1_000_000
        )

        let estimate = ApiPricingCatalog.estimate(
            modelUsage: [
                ApiModelUsage(
                    agent: .codex,
                    model: .named("gpt-5.6-sol"),
                    usage: codex
                ),
                ApiModelUsage(
                    agent: .claudeCode,
                    model: .named("claude-opus-5"),
                    usage: claude
                ),
            ],
            pricingDate: reviewed
        )

        // Codex: 5 + 30 + 6.25 + 0.50 = 41.75.
        // Claude: 5 + 25 + default/5m 6.25 + 0.50 = 36.75.
        // The 10.00 one-hour Claude rate must not be used without TTL detail.
        #expect(estimate.costUSD == decimal("78.50"))
        #expect(estimate.pricedTokens == 8_000_000)
        #expect(estimate.unpricedTokens == 0)
        #expect(estimate.isAvailable)
        #expect(!estimate.isPartial)
        #expect(estimate.formattedCostUSD == "$78.50")
    }

    @MainActor
    @Test func currentOdometerRowsUseTheDirectCodingAgentIDEntryPoint() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 27)
            )
        )
        let rows: [
            (agent: CodingAgentID, model: ModelName, usage: TokenUsage)
        ] = [
            (
                agent: .codex,
                model: .named("gpt-5.6-sol"),
                usage: usage(input: 1_000_000)
            ),
        ]

        let estimate = ApiPricingCatalog.estimate(rows, on: date)

        #expect(estimate.costUSD == decimal("5"))
        #expect(estimate.formattedCost(locale: Locale(identifier: "en-US")) == "$5.00")
    }

    @Test func unknownAndUnattributedModelsMakeTheEstimatePartial() {
        let estimate = ApiPricingCatalog.estimate(
            modelUsage: [
                ApiModelUsage(
                    agent: .codex,
                    model: .named("gpt-5.6-sol"),
                    usage: usage(input: 1_000_000)
                ),
                ApiModelUsage(
                    agent: .codex,
                    model: .named("codex-auto-review"),
                    usage: usage(output: 400)
                ),
                ApiModelUsage(
                    agent: .claudeCode,
                    model: .unattributed,
                    usage: usage(cacheRead: 600)
                ),
            ],
            pricingDate: reviewed
        )

        #expect(estimate.costUSD == decimal("5"))
        #expect(estimate.pricedTokens == 1_000_000)
        #expect(estimate.unpricedTokens == 1_000)
        #expect(estimate.isAvailable)
        #expect(estimate.isPartial)
        #expect(
            estimate.unpricedModels == [
                .model(agent: .claudeCode, model: .unattributed),
                .model(agent: .codex, model: .named("codex-auto-review")),
            ]
        )
    }

    @Test func totalUsageDisclosesAnyUnrepresentedRemainder() {
        let represented = usage(input: 100)
        let total = usage(input: 150, output: 25)
        let estimate = ApiPricingCatalog.estimate(
            modelUsage: [
                ApiModelUsage(
                    agent: .codex,
                    model: .named("gpt-5.6-sol"),
                    usage: represented
                ),
            ],
            totalUsage: total,
            pricingDate: reviewed
        )

        #expect(estimate.pricedTokens == 100)
        #expect(estimate.unpricedTokens == 75)
        #expect(estimate.unpricedModels == [.transcriptUnattributed])
    }

    @Test func kindSelectionFiltersBothCostAndDisclosure() {
        let estimate = ApiPricingCatalog.estimate(
            modelUsage: [
                ApiModelUsage(
                    agent: .codex,
                    model: .named("gpt-5.6-sol"),
                    usage: usage(
                        input: 1_000_000,
                        output: 1_000_000,
                        cacheWrite: 1_000_000,
                        cacheRead: 1_000_000
                    )
                ),
                ApiModelUsage(
                    agent: .codex,
                    model: .named("unknown-tier"),
                    usage: usage(input: 2, output: 3)
                ),
            ],
            pricingDate: reviewed,
            includedKinds: [.directInput, .output]
        )

        #expect(estimate.costUSD == decimal("35"))
        #expect(estimate.pricedTokens == 2_000_000)
        #expect(estimate.unpricedTokens == 5)

        let empty = ApiPricingCatalog.estimate(
            modelUsage: [
                ApiModelUsage(
                    agent: .codex,
                    model: .named("unknown-tier"),
                    usage: usage(input: 1)
                ),
            ],
            pricingDate: reviewed,
            includedKinds: []
        )
        #expect(!empty.isAvailable)
        #expect(!empty.isPartial)
        #expect(empty.unpricedModels.isEmpty)
    }

    @Test func finalAggregateRoundsUpOnceAndFormatsTwoDecimals() {
        let cases: [(String, String)] = [
            ("0", "$0.00"),
            ("1", "$1.00"),
            ("1.2300", "$1.23"),
            ("1.230001", "$1.24"),
            ("0.000001", "$0.01"),
            ("99.999", "$100.00"),
            ("100.001", "$100.01"),
        ]

        for (cost, expected) in cases {
            let estimate = ApiCostEstimate(
                costUSD: decimal(cost),
                pricedTokens: 1,
                unpricedTokens: 0,
                unpricedModels: []
            )
            #expect(estimate.formattedCostUSD == expected)
        }

        let unavailable = ApiCostEstimate(
            costUSD: decimal("0"),
            pricedTokens: 0,
            unpricedTokens: 10,
            unpricedModels: [.transcriptUnattributed]
        )
        #expect(unavailable.formattedCostUSD == "—")
    }

    private func usage(
        input: Int = 0,
        output: Int = 0,
        cacheWrite: Int = 0,
        cacheRead: Int = 0
    ) -> TokenUsage {
        var result = TokenUsage()
        result.inputTokens = input
        result.outputTokens = output
        result.cacheCreationTokens = cacheWrite
        result.cacheReadTokens = cacheRead
        result.responseCount =
            input + output + cacheWrite + cacheRead == 0 ? 0 : 1
        return result
    }

    private func openAI(
        _ rawInput: String,
        _ cacheWrite: String,
        _ cacheRead: String,
        _ output: String
    ) -> ApiTokenRates {
        let write = decimal(cacheWrite)
        return ApiTokenRates(
            rawInput: decimal(rawInput),
            cacheWrite: write,
            cacheWrite1Hour: write,
            cacheRead: decimal(cacheRead),
            output: decimal(output)
        )
    }

    private func anthropic(
        _ rawInput: String,
        _ cacheWrite: String,
        _ cacheWrite1Hour: String,
        _ cacheRead: String,
        _ output: String
    ) -> ApiTokenRates {
        ApiTokenRates(
            rawInput: decimal(rawInput),
            cacheWrite: decimal(cacheWrite),
            cacheWrite1Hour: decimal(cacheWrite1Hour),
            cacheRead: decimal(cacheRead),
            output: decimal(output)
        )
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(
            string: value,
            locale: Locale(identifier: "en_US_POSIX")
        )!
    }
}
