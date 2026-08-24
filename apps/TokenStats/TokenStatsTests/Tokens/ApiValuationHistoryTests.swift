//
//  ApiValuationHistoryTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

@MainActor
struct ApiValuationHistoryTests {
    @Test func mixedDateUsageKeepsTheHistoricalSolPrice() {
        let older = usage(input: 1_000_000)
        let current = usage(input: 1_000_000)
        var total = TokenUsage()
        total.add(older)
        total.add(current)
        let agent = TokenOdometerModel.AgentTokens(
            id: .codex,
            label: "Codex",
            usage: total,
            byModel: [
                .init(model: .named("gpt-5.6-sol"), usage: total),
            ],
            dailyByModel: [
                .init(
                    day: ApiPricingDate(year: 2026, month: 8, day: 23),
                    model: .named("gpt-5.6-sol"),
                    usage: older
                ),
                .init(
                    day: ApiPricingDate(year: 2026, month: 8, day: 24),
                    model: .named("gpt-5.6-sol"),
                    usage: current
                ),
            ]
        )

        let calculation = ApiValuationCalculation.make(
            perAgent: [agent],
            totalUsage: total,
            range: .sevenDays,
            fallbackPricingDate: ApiPricingDate(
                year: 2026,
                month: 8,
                day: 24
            )
        )

        #expect(calculation.estimate.costUSD == decimal("9"))
        #expect(
            calculation.snapshot.priceObservationIDs == [
                "openai.gpt-5.6-sol.observed-2026-08-04",
                "openai.gpt-5.6-sol.observed-2026-08-24",
            ]
        )
    }

    @Test func storeRetainsOneAuditSnapshotPerCatalogRevision() throws {
        let store = ApiValuationHistoryStore(
            defaults: InMemoryUserDefaults()
        )
        let current = snapshot(
            revision: "2026-08-24",
            cost: "4",
            calculatedAt: Date(timeIntervalSince1970: 200)
        )
        let prior = snapshot(
            revision: "2026-08-04",
            cost: "5",
            calculatedAt: Date(timeIntervalSince1970: 100)
        )
        store.save(prior)
        store.save(current)

        var loaded = store.load()
        #expect(loaded.map(\.catalogRevision) == ["2026-08-04", "2026-08-24"])
        #expect(loaded.map(\.exactCostUSD) == ["5", "4"])

        let updatedCurrent = snapshot(
            revision: "2026-08-24",
            cost: "4.5",
            calculatedAt: Date(timeIntervalSince1970: 300)
        )
        store.save(updatedCurrent)
        loaded = store.load()

        #expect(loaded.count == 2)
        #expect(try #require(loaded.last).exactCostUSD == "4.5")
        #expect(try #require(loaded.first).exactCostUSD == "5")
    }

    @Test func storeDoesNotOverwriteFutureSchemaHistory() throws {
        let defaults = InMemoryUserDefaults()
        let store = ApiValuationHistoryStore(defaults: defaults)
        let future = snapshot(
            schemaVersion: ApiValuationSnapshot.currentSchemaVersion + 1,
            revision: "future-revision",
            cost: "3",
            calculatedAt: Date(timeIntervalSince1970: 400)
        )
        let original = try JSONEncoder().encode([future])
        defaults.set(original, forKey: "tokens.apiValuationHistory.v1")

        let current = snapshot(
            revision: "2026-08-24",
            cost: "4",
            calculatedAt: Date(timeIntervalSince1970: 500)
        )
        #expect(store.save(current) == false)
        #expect(
            defaults.data(forKey: "tokens.apiValuationHistory.v1") == original
        )
        #expect(store.load().isEmpty)
    }

    private func snapshot(
        schemaVersion: Int = ApiValuationSnapshot.currentSchemaVersion,
        revision: String,
        cost: String,
        calculatedAt: Date
    ) -> ApiValuationSnapshot {
        ApiValuationSnapshot(
            schemaVersion: schemaVersion,
            scopeKey: "today|codex",
            catalogRevision: revision,
            range: .today,
            firstUsageDay: "2026-08-24",
            lastUsageDay: "2026-08-24",
            calculatedAt: calculatedAt,
            exactCostUSD: cost,
            pricedTokens: 1_000_000,
            unpricedTokens: 0,
            directInputTokens: 1_000_000,
            outputTokens: 0,
            cacheReadTokens: 0,
            priceObservationIDs: [
                "openai.gpt-5.6-sol.observed-\(revision)",
            ]
        )
    }

    private func usage(input: Int) -> TokenUsage {
        var result = TokenUsage()
        result.inputTokens = input
        result.responseCount = 1
        return result
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(
            string: value,
            locale: Locale(identifier: "en_US_POSIX")
        )!
    }
}
