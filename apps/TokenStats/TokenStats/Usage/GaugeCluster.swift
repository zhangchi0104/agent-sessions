//
//  GaugeCluster.swift
//  TokenStats
//
//  Lays out a group of Usage Window readings in whichever gauge style the user
//  picked. The one entry point every surface uses — the popover's agent
//  sections and the Appearance preview — so the style setting reaches all of
//  them from a single place.
//

import SwiftUI

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
