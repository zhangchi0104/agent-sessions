//
//  UsageGaugeViews.swift
//  TokenStats
//
//  The reusable gauge primitives shared by the popover and the Appearance
//  settings preview. One Usage Window reading (`GaugeContent`) can be drawn
//  three ways (`GaugeStyle`): a 270° dial, a closed ring, or a horizontal bar.
//  `GaugeCluster` lays a group of readings out as side-by-side dials/rings or a
//  stacked list of bars depending on the chosen style.
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
/// 2d 3h") for VoiceOver. `text` is a plain caption (credits' cap).
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
/// `UsageWindow`, from a credit balance, or as a neutral placeholder.
struct GaugeContent: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: GaugeSubtitle
    /// Percent still available (0–100); drives color + the spoken label.
    let percentRemaining: Double
    /// What the meter fills to, 0…1. Equals percentRemaining/100 for windows, but
    /// credits pass it explicitly so the dollar face and the fill stay in sync.
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

    /// Designated init, used for credits, the placeholder, and previews.
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

    /// A neutral, dataless reading (e.g. credits the plan doesn't expose).
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

/// A circular meter: either a 270° open arc (gap at the bottom, with ticks) or a
/// closed 360° ring. The visible empty track makes a partial reading read as a
/// *level on a dial* rather than something that could be mistaken for "maxed out".
struct CircularGauge<Center: View>: View {
    let progress: Double          // 0…1 of the meter that's filled
    let tint: Color
    let diameter: CGFloat
    var lineWidth: CGFloat = 6
    /// A closed ring when true; the 270° open dial when false.
    var isRing: Bool = false
    @ViewBuilder var center: () -> Center

    private var sweep: Double { isRing ? 1.0 : 0.75 }
    /// Ring fills clockwise from 12 o'clock; the arc's 90° gap sits at the bottom.
    private var rotation: Double { isRing ? -90 : 135 }
    private let tickFractions: [Double] = [0.25, 0.5, 0.75]

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(tint.opacity(0.16),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(rotation))

            if !isRing {
                ForEach(tickFractions, id: \.self) { fraction in
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: 1.5, height: lineWidth * 0.85)
                        .offset(y: -(diameter / 2 - lineWidth - 1))
                        .rotationEffect(.degrees(225 + fraction * 270))
                }
            }

            Circle()
                .trim(from: 0, to: sweep * min(max(progress, 0), 1))
                .stroke(tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(rotation))

            center()
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// A circular reading (dial or ring) with its number + "left" on the face and
/// the window name + reset countdown below.
struct CircularUsageGauge: View {
    let content: GaugeContent
    let isRing: Bool
    let diameter: CGFloat
    var lineWidth: CGFloat = 5

    private var tint: Color { content.tint }
    private var numberSize: CGFloat { diameter * 0.24 }

    var body: some View {
        VStack(spacing: 8) {
            CircularGauge(progress: content.isEnabled ? content.progress : 0,
                          tint: tint, diameter: diameter,
                          lineWidth: lineWidth, isRing: isRing) {
                face
            }

            VStack(spacing: 2) {
                Text(content.title)
                    .font((content.emphasized ? Font.body : .callout).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                subtitleLabel
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spokenLabel)
    }

    // The number stays pinned at the dial's center; the critical warning rides
    // above it as an overlay so its appearance never shifts the number.
    @ViewBuilder private var face: some View {
        VStack(spacing: 0) {
            Text(content.centerText)
                .font(.system(size: numberSize, weight: .semibold, design: .rounded)
                    .monospacedDigit())
                .foregroundStyle(.primary)            // neutral, always legible
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if content.isEnabled {
                Text("left")
                    .font(.system(size: numberSize * 0.4, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, lineWidth + 2)
        .overlay(alignment: .top) {
            if content.isEnabled && content.status == .critical {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: numberSize * 0.5))
                    .foregroundStyle(tint)
                    .offset(y: -numberSize * 0.62)
            }
        }
    }

    @ViewBuilder private var subtitleLabel: some View {
        switch content.subtitle {
        case .reset(let display, _):
            HStack(spacing: 2) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                Text(display)
                    .font(.callout.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        case .text(let text):
            Text(text)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        case .unavailable:
            Text("—")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A horizontal-bar reading: name + value on top, a proportional track below,
/// and the reset countdown beneath. Bars stack in a list (one per window).
struct BarUsageGauge: View {
    let content: GaugeContent

    private var tint: Color { content.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(content.title)
                    .font((content.emphasized ? Font.body : .callout).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if content.isEnabled && content.status == .critical {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(tint)
                }
                Spacer(minLength: 6)
                Text(content.centerText)
                    .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                if content.isEnabled {
                    Text("left")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Capsule()
                .fill(tint.opacity(0.16))
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * min(max(content.isEnabled ? content.progress : 0, 0), 1))
                    }
                }

            barSubtitle
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spokenLabel)
    }

    @ViewBuilder private var barSubtitle: some View {
        switch content.subtitle {
        case .reset(let display, _):
            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                Text(display)
                    .font(.callout.monospacedDigit())
            }
            .foregroundStyle(.secondary)
        case .text(let text):
            Text(text).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        case .unavailable:
            Text("—").font(.callout).foregroundStyle(.tertiary)
        }
    }
}

/// Lays a group of readings out per style: side-by-side dials/rings, or a
/// stacked list of bars. For circular styles the emphasized item is drawn larger.
struct GaugeCluster: View {
    let items: [GaugeContent]
    let style: GaugeStyle
    /// Circular sizing: emphasized items use `centerDiameter`, the rest `sideDiameter`.
    var sideDiameter: CGFloat = 70
    var centerDiameter: CGFloat = 104
    var sideLineWidth: CGFloat = 5
    var centerLineWidth: CGFloat = 7
    /// Horizontal spacing between circular gauges.
    var circularSpacing: CGFloat = 14

    var body: some View {
        Group {
            if style == .bar {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { BarUsageGauge(content: $0) }
                }
            } else {
                HStack(alignment: .center, spacing: circularSpacing) {
                    ForEach(items) { item in
                        CircularUsageGauge(
                            content: item,
                            isRing: style == .ring,
                            diameter: item.emphasized ? centerDiameter : sideDiameter,
                            lineWidth: item.emphasized ? centerLineWidth : sideLineWidth
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
