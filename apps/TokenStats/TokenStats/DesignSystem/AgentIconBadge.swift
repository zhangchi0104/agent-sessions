//
//  AgentIconBadge.swift
//  TokenStats
//
//  The rounded-tile brand glyph that leads a Coding Agent's row, following the
//  macOS System Settings convention of a colored icon before the label. Shared
//  by the Settings subscription rows, the Appearance order rows, and the onboarding
//  connect tiles.
//

import SwiftUI

/// A small rounded-tile glyph that anchors a Coding Agent's row.
struct AgentIconBadge: View {
    let id: CodingAgentID

    /// The mark and tile color are the agent's own, declared in its registry
    /// entry — the asset is a template SVG, so it tints white over the tile.
    private var brand: AgentBrand { id.integration.brand }

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(brand.tint)
            .frame(width: 26, height: 26)
            .overlay(
                Image(brand.assetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}
