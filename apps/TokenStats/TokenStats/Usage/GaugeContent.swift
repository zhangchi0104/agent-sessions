//
//  GaugeContent.swift
//  TokenStats
//
//  One Usage Window reading, decoupled from how it is drawn. Every gauge layout
//  renders this same value, so the number, the color, and the spoken label can
//  never disagree between the dial, the ring, and the bar.
//

import SwiftUI

/// How healthy a remaining-quota reading is. Drives color AND a redundant
/// non-color cue (a warning glyph at `.critical`) so the meaning survives for
/// red/green colorblind users.
enum GaugeStatus {
    case healthy   // plenty left
    case low       // getting low
    case critical  // nearly spent

    init(remaining: Double) {
        switch remaining {
        case 50...: self = .healthy
        case 30...: self = .low
        default: self = .critical
        }
    }

    var color: Color {
        switch self {
        case .healthy: return .green
        case .low: return .yellow
        case .critical: return .red
        }
    }
}

/// The line under (or beside) a dial. `reset` shows a ↻ glyph + compact duration
/// ("2d 3h") so it stays narrow, while carrying the full spoken form ("resets in
/// 2d 3h") for VoiceOver. `text` is a plain caption.
enum GaugeSubtitle: Equatable {
    case reset(display: String, spoken: String)
    case text(String)
    case unavailable

    static func forWindow(_ window: UsageWindow) -> GaugeSubtitle {
        guard let resetAt = window.resetAt else { return .unavailable }
        guard let compact = UsageFormatting.compactDuration(to: resetAt) else {
            return .reset(display: "now", spoken: "resets now")
        }
        return .reset(display: compact, spoken: UsageFormatting.resetCountdown(to: resetAt))
    }

    var spoken: String {
        switch self {
        case .reset(_, let spoken): return spoken
        case .text(let text): return text
        case .unavailable: return "reset time unknown"
        }
    }
}

/// One Usage Window's reading, decoupled from how it's drawn. Built from a
/// `UsageWindow` or as a neutral placeholder.
struct GaugeContent: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: GaugeSubtitle
    /// Percent still available (0–100); drives color + the spoken label.
    let percentRemaining: Double
    /// What the meter fills to, 0…1. Equals percentRemaining/100 for windows;
    /// readings whose face isn't a percentage pass it explicitly so the face
    /// and the fill stay in sync.
    let progress: Double
    let centerText: String
    var emphasized: Bool = false
    var isEnabled: Bool = true

    /// A window dial: fill and face both come from the window's remaining %.
    init(window: UsageWindow, emphasized: Bool = false) {
        self.title = window.label
        self.subtitle = .forWindow(window)
        self.percentRemaining = window.percentRemaining
        self.progress = window.percentRemaining / 100
        self.centerText = UsageFormatting.remainingPercentText(window.percentRemaining)
        self.emphasized = emphasized
    }

    /// Designated init, used for the placeholder and previews.
    init(title: String, subtitle: GaugeSubtitle, percentRemaining: Double, progress: Double,
         centerText: String, emphasized: Bool = false, isEnabled: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.percentRemaining = percentRemaining
        self.progress = progress
        self.centerText = centerText
        self.emphasized = emphasized
        self.isEnabled = isEnabled
    }

    /// A neutral, dataless reading (e.g. a quota the plan doesn't expose).
    static func placeholder(title: String) -> GaugeContent {
        GaugeContent(title: title, subtitle: .unavailable, percentRemaining: 0,
                     progress: 0, centerText: "—", isEnabled: false)
    }

    var status: GaugeStatus { GaugeStatus(remaining: percentRemaining) }
    var tint: Color { isEnabled ? status.color : .secondary }

    /// Spoken VoiceOver label shared by every layout.
    var spokenLabel: String {
        guard isEnabled else { return "\(title), not available" }
        let lowNote = status == .critical ? ", running low" : ""
        return "\(title), \(centerText) left\(lowNote), \(subtitle.spoken)"
    }
}
