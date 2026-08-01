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

    private let englishLocale = Locale(identifier: "en-US")

    private var englishLocalizer: AppLocalizer {
        AppLocalizer(locale: englishLocale)
    }

    private func snapshot(percent: Double = 24) -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(label: "5-hour", percentConsumed: percent,
                                  resetAt: Date(timeIntervalSince1970: 1716800000))],
            fetchedAt: Date(timeIntervalSince1970: 1716700000)
        )
    }

    @Test func claudeOnlyMenuBarSummaryShowsRemainingPercentage() {
        let text = MenuBarSummary.text(
            for: [
                CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
            ],
            locale: englishLocale
        )

        #expect(text == "76%")
    }

    @Test func multipleMenuBarSummariesRenderSeparateAgentReadings() {
        let text = MenuBarSummary.text(
            for: [
                CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
                CodingAgentUsageSummary(shortLabel: "X", state: .fresh(snapshot(percent: 12))),
            ],
            locale: englishLocale
        )

        #expect(text == "C: 76% X: 88%")
    }

    @Test func signedOutAgentDoesNotReserveMenuBarSlot() {
        let text = MenuBarSummary.text(
            for: [
                CodingAgentUsageSummary(shortLabel: "C", state: .fresh(snapshot(percent: 24))),
                CodingAgentUsageSummary(shortLabel: "X", state: .signedOut),
            ],
            locale: englishLocale
        )

        #expect(text == "76%")
    }

    @Test func allSignedOutAgentsUseNeutralMenuBarPlaceholder() {
        let text = MenuBarSummary.text(
            for: [
                CodingAgentUsageSummary(shortLabel: "C", state: .signedOut),
                CodingAgentUsageSummary(shortLabel: "X", state: .signedOut),
            ],
            locale: englishLocale
        )

        #expect(text == "—")
    }

    @Test func resetCountdownUsesDaysAndHoursPastADay() {
        let now = Date(timeIntervalSince1970: 0)
        let resetAt = now.addingTimeInterval((2 * 24 + 3) * 3600)

        #expect(
            UsageFormatting.resetCountdown(
                to: resetAt,
                now: now,
                localizer: englishLocalizer
            ) == "resets in 2 days, 3 hours"
        )
    }

    @Test func resetCountdownUsesHoursAndMinutesUnderADay() {
        let now = Date(timeIntervalSince1970: 0)
        let resetAt = now.addingTimeInterval(4 * 3600 + 12 * 60)

        #expect(
            UsageFormatting.resetCountdown(
                to: resetAt,
                now: now,
                localizer: englishLocalizer
            ) == "resets in 4 hours, 12 minutes"
        )
    }

    @Test func resetCountdownReadsResetsNowOncePast() {
        let now = Date(timeIntervalSince1970: 60)
        let resetAt = Date(timeIntervalSince1970: 0)

        #expect(
            UsageFormatting.resetCountdown(
                to: resetAt,
                now: now,
                localizer: englishLocalizer
            ) == "resets now"
        )
    }

    @Test func remainingPercentTextFloorsSoItNeverOverstatesWhatsLeft() {
        // 29.9% left must not round up to a reassuring "30%"; a hair under full
        // must read "99%", matching a not-quite-complete arc.
        #expect(UsageFormatting.remainingPercentText(29.9, locale: englishLocale) == "29%")
        #expect(UsageFormatting.remainingPercentText(99.6, locale: englishLocale) == "99%")
        #expect(UsageFormatting.remainingPercentText(100, locale: englishLocale) == "100%")
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
    @Test func defaultsArePrimaryClaudeDialAndUnfilteredTodayValues() {
        withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            #expect(settings.primaryAgent == .claudeCode)
            #expect(settings.gaugeStyle == .arc270)
            #expect(Set(settings.order) == Set(CodingAgentID.allCases))
            #expect(settings.usageVisibleAgents == Set(CodingAgentID.allCases))
            #expect(settings.tokensVisibleAgents == Set(CodingAgentID.allCases))
            #expect(settings.menuBarVisibleAgents == Set(CodingAgentID.allCases))
            #expect(settings.tokenSummaryMetric == .billingTokens)
            #expect(settings.selectedTokenKinds == Set(TokenKind.allCases))
            #expect(settings.tokenValueDisplay == .value)
            #expect(settings.selectedTokenRange == .today)
        }
    }

    @MainActor
    @Test func agentVisibilityPersistsIndependentlyPerSurface() {
        withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            #expect(settings.setVisible(.codex, on: .usage, isVisible: false))
            #expect(settings.setVisible(.claudeCode, on: .tokens, isVisible: false))
            #expect(settings.setVisible(.codex, on: .menuBar, isVisible: false))

            let reloaded = AppearanceSettings(defaults: defaults)
            #expect(reloaded.usageVisibleAgents == [.claudeCode])
            #expect(reloaded.tokensVisibleAgents == [.codex])
            #expect(reloaded.menuBarVisibleAgents == [.claudeCode])
            #expect(reloaded.usageDisplayOrder == [.claudeCode])
            #expect(reloaded.tokensDisplayOrder == [.codex])
            #expect(reloaded.menuBarDisplayOrder == [.claudeCode])
        }
    }

    @MainActor
    @Test func hidingTheLastAgentIsRejectedAndRepeatedChangesAreIdempotent() {
        withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)

            #expect(settings.setVisible(.codex, on: .usage, isVisible: false))
            #expect(settings.setVisible(.codex, on: .usage, isVisible: false))
            #expect(!settings.setVisible(.claudeCode, on: .usage, isVisible: false))
            #expect(settings.usageVisibleAgents == [.claudeCode])

            #expect(settings.setVisible(.claudeCode, on: .tokens, isVisible: true))
            #expect(settings.setVisible(.codex, on: .tokens, isVisible: false))
            #expect(!settings.setVisible(.claudeCode, on: .tokens, isVisible: false))
            #expect(settings.tokensVisibleAgents == [.claudeCode])
        }
    }

    @MainActor
    @Test func reenabledAgentReturnsToTheSavedOrderAndPrimaryMayBeSurfaceHidden() {
        withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            settings.primaryAgent = .codex

            #expect(settings.setVisible(.codex, on: .usage, isVisible: false))
            #expect(settings.usageDisplayOrder == [.claudeCode])
            #expect(settings.setVisible(.codex, on: .usage, isVisible: true))
            #expect(settings.usageDisplayOrder == [.codex, .claudeCode])

            // The global Primary preference is unchanged by a per-surface
            // visibility choice.
            #expect(settings.primaryAgent == .codex)
        }
    }

    @MainActor
    @Test func corruptVisibleAgentPreferenceRepairsToClaude() {
        withDefaults { defaults in
            defaults.set([], forKey: "appearance.usageVisibleAgents")
            defaults.set(["future-agent"], forKey: "appearance.tokensVisibleAgents")
            defaults.set(["codex", "future-agent"], forKey: "appearance.menuBarVisibleAgents")

            let settings = AppearanceSettings(defaults: defaults)

            #expect(settings.usageVisibleAgents == [.claudeCode])
            #expect(settings.tokensVisibleAgents == [.claudeCode])
            #expect(settings.menuBarVisibleAgents == [.codex])
            #expect(defaults.array(forKey: "appearance.usageVisibleAgents") as? [String]
                    == ["claudeCode"])
            #expect(defaults.array(forKey: "appearance.tokensVisibleAgents") as? [String]
                    == ["claudeCode"])
        }
    }

    @MainActor
    @Test func choicesPersistAcrossReload() {
        withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            settings.primaryAgent = .codex
            settings.gaugeStyle = .bar
            settings.tokenSummaryMetric = .apiEquivalent
            #expect(settings.setTokenKind(.cacheRead, isSelected: false))
            settings.tokenValueDisplay = .valueAndPercentage
            settings.selectedTokenRange = .thirtyDays
            let codexIndex = settings.order.firstIndex(of: .codex)!
            settings.move(fromOffsets: IndexSet(integer: codexIndex), toOffset: 0)

            let reloaded = AppearanceSettings(defaults: defaults)
            #expect(reloaded.primaryAgent == .codex)
            #expect(reloaded.gaugeStyle == .bar)
            #expect(reloaded.tokenSummaryMetric == .apiEquivalent)
            #expect(reloaded.selectedTokenKinds == Set([.directInput, .output, .cacheWrite]))
            #expect(reloaded.tokenValueDisplay == .valueAndPercentage)
            #expect(reloaded.selectedTokenRange == .thirtyDays)
            #expect(reloaded.order.first == .codex)
            #expect(reloaded.displayOrder == [.codex, .claudeCode])
        }
    }

    @MainActor
    @Test func theLastTokenKindCannotBeDisabled() {
        withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            #expect(settings.setTokenKind(.output, isSelected: false))
            #expect(settings.setTokenKind(.cacheWrite, isSelected: false))
            #expect(settings.setTokenKind(.cacheRead, isSelected: false))

            #expect(settings.selectedTokenKinds == [.directInput])
            #expect(!settings.setTokenKind(.directInput, isSelected: false))
            #expect(settings.selectedTokenKinds == [.directInput])

            let reloaded = AppearanceSettings(defaults: defaults)
            #expect(reloaded.selectedTokenKinds == [.directInput])
        }
    }

    @MainActor
    @Test func invalidStoredTokenPreferencesFallBackSafely() {
        withDefaults { defaults in
            defaults.set(["future-kind"], forKey: "appearance.selectedTokenKinds")
            defaults.set("future-mode", forKey: "appearance.tokenValueDisplay")
            defaults.set("future-range", forKey: "appearance.selectedTokenRange")

            let settings = AppearanceSettings(defaults: defaults)

            #expect(settings.selectedTokenKinds == Set(TokenKind.allCases))
            #expect(settings.tokenValueDisplay == .value)
            #expect(settings.selectedTokenRange == .today)
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
