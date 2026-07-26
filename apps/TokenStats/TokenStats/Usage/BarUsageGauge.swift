//
//  BarUsageGauge.swift
//  TokenStats
//
//  The horizontal-bar gauge layout, for users who read a stacked list faster
//  than a row of dials.
//

import SwiftUI

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
