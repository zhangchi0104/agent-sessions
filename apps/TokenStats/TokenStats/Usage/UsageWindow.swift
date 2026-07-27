//
//  UsageWindow.swift
//  TokenStats
//
//  A normalized, agent-agnostic view of one Usage Window row.
//

import Foundation

struct UsageWindow: Equatable, Codable {
    /// Human-facing name for the quota row, e.g. "5-hour" or "Weekly".
    let label: String
    /// Fraction of the Limit consumed, expressed 0–100.
    let percentConsumed: Double
    /// When this window's usage resets, if the provider exposes it.
    let resetAt: Date?

    init(label: String, percentConsumed: Double, resetAt: Date?) {
        self.label = label
        self.percentConsumed = percentConsumed
        self.resetAt = resetAt
    }

    /// Fraction of the Limit still available, expressed 0–100.
    var percentRemaining: Double {
        min(max(100 - percentConsumed, 0), 100)
    }
}
