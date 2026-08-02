//
//  UsageFormatting.swift
//  TokenStats
//
//  Presentation helpers — menu-bar summaries, countdown to reset, relative
//  "updated" age, and labels derived from AppState.
//

import Foundation

struct CodingAgentUsageSummary: Equatable {
    let shortLabel: String
    let state: AppState
}

enum MenuBarSummary {
    static func text(
        for agents: [CodingAgentUsageSummary],
        locale: Locale
    ) -> String {
        let visibleAgents = agents.filter(\.isVisibleInMenuBar)
        guard let first = visibleAgents.first else { return "—" }
        if visibleAgents.count == 1 {
            return UsageFormatting.menuBarText(for: first.state, locale: locale)
        }
        return visibleAgents.map { agent in
            "\(agent.shortLabel): \(UsageFormatting.menuBarText(for: agent.state, locale: locale))"
        }.joined(separator: " ")
    }
}

private extension CodingAgentUsageSummary {
    var isVisibleInMenuBar: Bool {
        if case .signedOut = state { return false }
        return true
    }
}

enum UsageFormatting {

    /// Whole-percent text for a *remaining* value, floored so we never overstate
    /// how much is left (29.9% left reads "29%", not "30%") and a hair under full
    /// reads "99%" rather than a "100%" that disagrees with a not-quite-full arc.
    static func remainingPercentText(_ percent: Double, locale: Locale) -> String {
        let floored = Int(min(max(percent, 0), 100).rounded(.down))
        return (Double(floored) / 100).formatted(
            .percent
                .precision(.fractionLength(0))
                .locale(locale)
        )
    }

    /// The compact menu-bar text: the 5-hour percent remaining, or a neutral placeholder.
    static func menuBarText(for state: AppState, locale: Locale) -> String {
        switch state {
        case .signedOut:
            return "—"
        case .loading:
            return "…"
        case .fresh(let snapshot), .staleDisclosed(let snapshot):
            guard let primary = snapshot.windows.first else { return "—" }
            return remainingPercentText(primary.percentRemaining, locale: locale)
        }
    }

    /// Compact reset duration for a gauge face, e.g. "2d 3h", "4h 52m", "8m" —
    /// nil once the reset has passed. Paired with a ↻ glyph in the UI so it stays
    /// narrow enough to sit under a small dial.
    static func compactDuration(
        to resetAt: Date,
        now: Date = Date(),
        locale: Locale
    ) -> String? {
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return compactDuration(remaining, locale: locale)
    }

    /// The spoken/full countdown that stays legible past 24h, e.g. "resets in
    /// 2 days, 3 hours", "resets in 4 hours, 12 minutes", "resets now". Used for tooltips and VoiceOver,
    /// where a bare "164:00"-style HH:MM clock would read as a malformed timestamp.
    static func resetCountdown(
        to resetAt: Date,
        now: Date = Date(),
        localizer: AppLocalizer
    ) -> String {
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else {
            return localizer.localized(
                LocalizedStringResource.usageResetNow
            )
        }
        let duration = spokenDuration(remaining, locale: localizer.locale)
        return localizer.localized(
            LocalizedStringResource.usageResetInDuration(duration)
        )
    }

    private static func compactDuration(_ seconds: TimeInterval, locale: Locale) -> String {
        durationRoundedDownForDisplay(seconds).formatted(
            .units(
                allowed: [.days, .hours, .minutes],
                width: .narrow,
                maximumUnitCount: 2,
                zeroValueUnits: .hide
            )
            .locale(locale)
        )
    }

    private static func spokenDuration(_ seconds: TimeInterval, locale: Locale) -> String {
        durationRoundedDownForDisplay(seconds).formatted(
            .units(
                allowed: [.days, .hours, .minutes],
                width: .wide,
                maximumUnitCount: 2,
                zeroValueUnits: .hide
            )
            .locale(locale)
        )
    }

    /// `Duration.UnitsFormatStyle` rounds when `maximumUnitCount` hides lower
    /// units. A remaining-time display must never promise more time than is
    /// actually left, so remove those units before asking Foundation to localize
    /// the result: minutes below one day, hours once days are visible.
    private static func durationRoundedDownForDisplay(_ seconds: TimeInterval) -> Duration {
        let wholeSeconds = max(Int64(seconds.rounded(.down)), 60)
        let granularity: Int64 = wholeSeconds >= 24 * 60 * 60 ? 60 * 60 : 60
        return .seconds((wholeSeconds / granularity) * granularity)
    }

    /// "12m ago", "2h ago", "just now".
    static func relativeAge(
        of date: Date,
        locale: Locale
    ) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return AppLocalizer(locale: locale).localized(
                LocalizedStringResource.usageUpdatedJustNow
            )
        }
        return date.formatted(
            .relative(presentation: .numeric, unitsStyle: .abbreviated)
                .locale(locale)
        )
    }
}
