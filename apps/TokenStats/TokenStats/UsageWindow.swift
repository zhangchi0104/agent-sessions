//
//  UsageWindow.swift
//  TokenStats
//
//  A normalized, agent-agnostic view of one usage quota row.
//  Most rows are Usage Windows (see CONTEXT.md); Claude Code usage credits can
//  also be displayed here when the endpoint exposes them as the active meter.
//

import Foundation

struct UsageWindow: Equatable, Codable {
    /// Human-facing name for the quota row, e.g. "5-hour", "Weekly", or "Usage credits".
    let label: String
    /// Fraction of the Limit consumed, expressed 0–100.
    let percentConsumed: Double
    /// When this window's usage resets, if the provider exposes it.
    let resetAt: Date?
    /// Optional provider-specific detail for non-reset quota meters.
    let detailText: String?

    init(label: String, percentConsumed: Double, resetAt: Date?, detailText: String? = nil) {
        self.label = label
        self.percentConsumed = percentConsumed
        self.resetAt = resetAt
        self.detailText = detailText
    }
}
