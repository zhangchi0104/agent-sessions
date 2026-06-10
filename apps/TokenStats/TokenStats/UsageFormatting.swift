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
    static func text(for agents: [CodingAgentUsageSummary]) -> String {
        let visibleAgents = agents.filter(\.isVisibleInMenuBar)
        guard let first = visibleAgents.first else { return "—" }
        if visibleAgents.count == 1 {
            return UsageFormatting.menuBarText(for: first.state)
        }
        return visibleAgents.map { agent in
            "\(agent.shortLabel): \(UsageFormatting.menuBarText(for: agent.state))"
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
    static func remainingPercentText(_ percent: Double) -> String {
        "\(Int(min(max(percent, 0), 100).rounded(.down)))%"
    }

    /// The compact menu-bar text: the 5-hour percent remaining, or a neutral placeholder.
    static func menuBarText(for state: AppState) -> String {
        switch state {
        case .signedOut:
            return "—"
        case .loading:
            return "…"
        case .fresh(let snapshot), .staleDisclosed(let snapshot):
            guard let primary = snapshot.windows.first else { return "—" }
            return remainingPercentText(primary.percentRemaining)
        }
    }

    /// Compact reset duration for a gauge face, e.g. "2d 3h", "4h 52m", "8m" —
    /// nil once the reset has passed. Paired with a ↻ glyph in the UI so it stays
    /// narrow enough to sit under a small dial.
    static func compactDuration(to resetAt: Date, now: Date = Date()) -> String? {
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return coarseDuration(remaining)
    }

    /// The spoken/full countdown that stays legible past 24h, e.g. "resets in
    /// 2d 3h", "resets in 4h 12m", "resets now". Used for tooltips and VoiceOver,
    /// where a bare "164:00"-style HH:MM clock would read as a malformed timestamp.
    static func resetCountdown(to resetAt: Date, now: Date = Date()) -> String {
        guard let duration = compactDuration(to: resetAt, now: now) else { return "resets now" }
        return "resets in \(duration)"
    }

    private static func coarseDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(max(minutes, 1))m"
    }

    /// "12m ago", "2h ago", "just now".
    static func relativeAge(of date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 60 else { return "just now" }
        return "\(durationText(elapsed)) ago"
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }
}
