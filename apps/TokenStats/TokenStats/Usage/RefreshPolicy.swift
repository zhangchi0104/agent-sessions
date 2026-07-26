//
//  RefreshPolicy.swift
//  TokenStats
//
//  Pure decision: given when we last fetched, what triggered this check, and
//  how many consecutive failures we've had, decide whether to fetch now and
//  how long until the next scheduled timer. Exponential backoff applies to
//  failures only; a successful fetch resets the caller's failure count.
//

import Foundation

enum RefreshTrigger {
    case timer
    case wake
    case popoverOpen
    case manual
}

struct RefreshDecision: Equatable {
    let shouldFetch: Bool
    let nextInterval: TimeInterval
}

enum RefreshPolicy {

    /// Background poll cadence when healthy.
    static let baseInterval: TimeInterval = 30 * 60
    /// Ceiling for exponential backoff so a long failure streak can't push the
    /// interval to an absurd (or non-finite, via `pow` overflow) value that
    /// effectively kills the timer.
    static let maxInterval: TimeInterval = 6 * 60 * 60

    static func decide(
        trigger: RefreshTrigger,
        lastFetch: Date?,
        now: Date,
        consecutiveFailures: Int
    ) -> RefreshDecision {
        // Backoff applies to failures only; 0 failures => base interval.
        let interval = min(baseInterval * pow(2, Double(max(0, consecutiveFailures))), maxInterval)

        let shouldFetch: Bool
        switch trigger {
        case .timer:
            if let lastFetch {
                shouldFetch = now.timeIntervalSince(lastFetch) >= interval
            } else {
                shouldFetch = true
            }
        case .wake, .popoverOpen, .manual:
            shouldFetch = true
        }
        return RefreshDecision(shouldFetch: shouldFetch, nextInterval: interval)
    }
}
