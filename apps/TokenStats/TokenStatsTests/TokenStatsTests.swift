//
//  TokenStatsTests.swift
//  TokenStatsTests
//
//  Created by 张弛 on 2026/5/27.
//

import Testing
import Foundation
@testable import TokenStats

struct TokenStatsTests {

    private func snapshot(percent: Double = 24) -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(label: "5-hour", percentConsumed: percent,
                                  resetAt: Date(timeIntervalSince1970: 1716800000))],
            fetchedAt: Date(timeIntervalSince1970: 1716700000)
        )
    }

    @Test func claudeOnlyMenuBarSummaryPreservesCurrentPercentage() {
        let text = MenuBarSummary.text(for: [
            CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
        ])

        #expect(text == "24%")
    }

    @Test func multipleMenuBarSummariesRenderSeparateAgentReadings() {
        let text = MenuBarSummary.text(for: [
            CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
            CodingAgentUsageSummary(shortLabel: "X", state: .fresh(snapshot(percent: 12))),
        ])

        #expect(text == "C: 24% X: 12%")
    }

    @Test func signedOutAgentDoesNotReserveMenuBarSlot() {
        let text = MenuBarSummary.text(for: [
            CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
            CodingAgentUsageSummary(shortLabel: "X", state: .signedOut),
        ])

        #expect(text == "24%")
    }

    @Test func allSignedOutAgentsUseNeutralMenuBarPlaceholder() {
        let text = MenuBarSummary.text(for: [
            CodingAgentUsageSummary(shortLabel: "C", state: .signedOut),
            CodingAgentUsageSummary(shortLabel: "X", state: .signedOut),
        ])

        #expect(text == "—")
    }

    @Test func resetTimerTextUsesHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 0)
        let resetAt = now.addingTimeInterval((2 * 60 + 14) * 60)

        #expect(UsageFormatting.timerText(to: resetAt, now: now) == "02:14")
    }

    @Test func resetTimerTextRoundsPartialMinutesUp() {
        let now = Date(timeIntervalSince1970: 0)
        let resetAt = now.addingTimeInterval(61)

        #expect(UsageFormatting.timerText(to: resetAt, now: now) == "00:02")
    }

    @Test func resetTimerTextUsesZeroWhenResetHasPassed() {
        let now = Date(timeIntervalSince1970: 60)
        let resetAt = Date(timeIntervalSince1970: 0)

        #expect(UsageFormatting.timerText(to: resetAt, now: now) == "00:00")
    }

}

struct LastKnownUsageStoreTests {

    private func snapshot(percent: Double) -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(label: "5-hour", percentConsumed: percent,
                                  resetAt: Date(timeIntervalSince1970: 1716800000))],
            fetchedAt: Date(timeIntervalSince1970: 1716700000)
        )
    }

    private func withStore(_ test: (LastKnownUsageStore) -> Void) {
        let suiteName = "TokenStatsTests.LastKnownUsageStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LastKnownUsageStore(defaults: defaults)

        test(store)
    }

    @Test func storesLastKnownUsagePerCodingAgent() {
        let claudeSnapshot = snapshot(percent: 24)
        let codexSnapshot = snapshot(percent: 12)

        withStore { store in
            store.save(claudeSnapshot, for: .claudeCode)
            store.save(codexSnapshot, for: .codex)

            #expect(store.load(for: .claudeCode) == claudeSnapshot)
            #expect(store.load(for: .codex) == codexSnapshot)
        }
    }

    @Test func clearsOnlyTheTargetCodingAgentsLastKnownUsage() {
        let claudeSnapshot = snapshot(percent: 24)
        let codexSnapshot = snapshot(percent: 12)

        withStore { store in
            store.save(claudeSnapshot, for: .claudeCode)
            store.save(codexSnapshot, for: .codex)

            store.clear(for: .codex)

            #expect(store.load(for: .claudeCode) == claudeSnapshot)
            #expect(store.load(for: .codex) == nil)
        }
    }
}
