//
//  TokenRange.swift
//  TokenStats
//
//  The windows the Token Odometer reports over. Rolling, not calendar-aligned,
//  and capped at 30 days: Claude prunes its transcripts at about a month while
//  Codex does not, so a longer window would set a few weeks of one Coding Agent
//  beside months of the other and present it as a comparison.
//

import Foundation

enum TokenRange: CaseIterable, Hashable {
    case today
    case sevenDays
    case thirtyDays

    /// How many local days the window spans, today inclusive.
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

    /// Local midnight at the start of the window.
    func start(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday
    }
}
