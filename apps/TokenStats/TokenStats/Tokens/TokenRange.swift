//
//  TokenRange.swift
//  TokenStats
//
//  The spans the Token Odometer reports over. Rolling, not calendar-aligned,
//  and capped at 30 days: Claude prunes its transcripts at about a month while
//  Codex does not, so a longer span would set a few weeks of one Coding Agent
//  beside months of the other and present it as a comparison.
//
//  Deliberately never called a *window*: CONTEXT.md reserves that word for the
//  Usage Window, which is a quota concept with a Limit and a reset. A range
//  here is neither.
//

import Foundation

nonisolated enum TokenRange: String, CaseIterable, Codable, Hashable, Sendable {
    case today
    case sevenDays
    case thirtyDays

    /// How many local days the range spans, today inclusive.
    var days: Int {
        switch self {
        case .today: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        }
    }

    var label: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        }
    }

    /// Local midnight at the start of the range, measured back from `now`.
    /// `Calendar.current` is right for the boundary — it carries the user's own
    /// time zone — and the reader keys entries through a formatter pinned to a
    /// Gregorian calendar in that same time zone, so the boundary and the day
    /// keys inside it agree. Day arithmetic (rather than subtracting 86,400s)
    /// is what keeps a 23- or 25-hour DST day landing on midnight.
    func start(from now: Date) -> Date {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return Calendar.current.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday
    }
}
