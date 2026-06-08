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

    /// "42%" for the primary (5-hour) window, rounded.
    static func percentText(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }

    /// The compact menu-bar text: the 5-hour percent, or a neutral placeholder.
    static func menuBarText(for state: AppState) -> String {
        switch state {
        case .signedOut:
            return "—"
        case .loading:
            return "…"
        case .fresh(let snapshot), .staleDisclosed(let snapshot):
            guard let primary = snapshot.windows.first else { return "—" }
            return percentText(primary.percentConsumed)
        }
    }

    /// "resets in 2h 14m" (or "resetting now" once past).
    static func countdown(to resetAt: Date, now: Date = Date()) -> String {
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else { return "resetting now" }
        return "resets in \(durationText(remaining))"
    }

    /// Compact countdown for small gauges, e.g. "02:14".
    static func timerText(to resetAt: Date, now: Date = Date()) -> String {
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else { return "00:00" }
        let totalSeconds = Int(remaining.rounded(.up))
        let totalMinutes = Int(ceil(Double(totalSeconds) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// "12m ago", "2h ago", "just now".
    static func relativeAge(of date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 60 else { return "just now" }
        return "\(durationText(elapsed)) ago"
    }

    /// Absolute reset time for the secondary detail, e.g. "3:45 PM".
    static func absoluteTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
