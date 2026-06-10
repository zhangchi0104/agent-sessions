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

    @Test func claudeOnlyMenuBarSummaryShowsRemainingPercentage() {
        let text = MenuBarSummary.text(for: [
            CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
        ])

        #expect(text == "76%")
    }

    @Test func multipleMenuBarSummariesRenderSeparateAgentReadings() {
        let text = MenuBarSummary.text(for: [
            CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
            CodingAgentUsageSummary(shortLabel: "X", state: .fresh(snapshot(percent: 12))),
        ])

        #expect(text == "C: 76% X: 88%")
    }

    @Test func signedOutAgentDoesNotReserveMenuBarSlot() {
        let text = MenuBarSummary.text(for: [
            CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
            CodingAgentUsageSummary(shortLabel: "X", state: .signedOut),
        ])

        #expect(text == "76%")
    }

    @Test func allSignedOutAgentsUseNeutralMenuBarPlaceholder() {
        let text = MenuBarSummary.text(for: [
            CodingAgentUsageSummary(shortLabel: "C", state: .signedOut),
            CodingAgentUsageSummary(shortLabel: "X", state: .signedOut),
        ])

        #expect(text == "—")
    }

    @Test func resetCountdownUsesDaysAndHoursPastADay() {
        let now = Date(timeIntervalSince1970: 0)
        let resetAt = now.addingTimeInterval((2 * 24 + 3) * 3600)

        #expect(UsageFormatting.resetCountdown(to: resetAt, now: now) == "resets in 2d 3h")
    }

    @Test func resetCountdownUsesHoursAndMinutesUnderADay() {
        let now = Date(timeIntervalSince1970: 0)
        let resetAt = now.addingTimeInterval(4 * 3600 + 12 * 60)

        #expect(UsageFormatting.resetCountdown(to: resetAt, now: now) == "resets in 4h 12m")
    }

    @Test func resetCountdownReadsResetsNowOncePast() {
        let now = Date(timeIntervalSince1970: 60)
        let resetAt = Date(timeIntervalSince1970: 0)

        #expect(UsageFormatting.resetCountdown(to: resetAt, now: now) == "resets now")
    }

    @Test func remainingPercentTextFloorsSoItNeverOverstatesWhatsLeft() {
        // 29.9% left must not round up to a reassuring "30%"; a hair under full
        // must read "99%", matching a not-quite-complete arc.
        #expect(UsageFormatting.remainingPercentText(29.9) == "29%")
        #expect(UsageFormatting.remainingPercentText(99.6) == "99%")
        #expect(UsageFormatting.remainingPercentText(100) == "100%")
    }

}

struct AppearanceSettingsTests {

    @Test func displayOrderLeadsWithPrimaryThenSavedOrder() {
        let resolved = AgentDisplayOrder.resolve(primary: .codex, order: [.claudeCode, .codex])
        #expect(resolved == [.codex, .claudeCode])
    }

    @Test func displayOrderKeepsSavedOrderWhenPrimaryIsAlreadyFirst() {
        let resolved = AgentDisplayOrder.resolve(primary: .claudeCode, order: [.claudeCode, .codex])
        #expect(resolved == [.claudeCode, .codex])
    }

    @Test func displayOrderAppendsAgentsMissingFromTheSavedOrder() {
        // A stored order predating a newly added agent must still surface it.
        let resolved = AgentDisplayOrder.resolve(primary: .claudeCode, order: [.claudeCode])
        #expect(Set(resolved) == Set(CodingAgentID.allCases))
        #expect(resolved.first == .claudeCode)
    }

    @MainActor
    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "TokenStatsTests.Appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        test(defaults)
    }

    @MainActor
    @Test func defaultsArePrimaryClaudeAndDialStyle() {
        withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            #expect(settings.primaryAgent == .claudeCode)
            #expect(settings.gaugeStyle == .arc270)
            #expect(Set(settings.order) == Set(CodingAgentID.allCases))
        }
    }

    @MainActor
    @Test func choicesPersistAcrossReload() {
        withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            settings.primaryAgent = .codex
            settings.gaugeStyle = .bar
            let codexIndex = settings.order.firstIndex(of: .codex)!
            settings.move(fromOffsets: IndexSet(integer: codexIndex), toOffset: 0)

            let reloaded = AppearanceSettings(defaults: defaults)
            #expect(reloaded.primaryAgent == .codex)
            #expect(reloaded.gaugeStyle == .bar)
            #expect(reloaded.order.first == .codex)
            #expect(reloaded.displayOrder == [.codex, .claudeCode])
        }
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
