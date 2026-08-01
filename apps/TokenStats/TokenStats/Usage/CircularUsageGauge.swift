//
//  CircularUsageGauge.swift
//  TokenStats
//
//  The circular gauge layouts: a 270° open dial (the default) and a closed
//  ring. `CircularGauge` is the bare meter; `CircularUsageGauge` dresses it with
//  the number on the face and the window name + reset countdown below.
//

import SwiftUI

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
                Text(
                    LocalizedStringResource.usageGaugeRemainingSuffix
                )
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
            // i18n-ignore: Universal unavailable-value glyph, not natural-language copy.
            Text(verbatim: "—")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}
