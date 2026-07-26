//
//  AgentIconBadge.swift
//  TokenStats
//
//  The rounded-tile brand glyph that leads a Coding Agent's row, following the
//  macOS System Settings convention of a colored icon before the label. Shared
//  by the Settings account rows, the Appearance order rows, and the onboarding
//  connect tiles.
//

import SwiftUI

/// A small rounded-tile glyph that anchors a Coding Agent's row.
struct AgentIconBadge: View {
    let id: CodingAgentID

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint)
            .frame(width: 26, height: 26)
            .overlay(
                Image(logo)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }

    /// The brand mark in the asset catalog (template SVGs that tint white).
    private var logo: String {
        switch id {
        case .claudeCode: return "BrandClaude" // Anthropic / Claude spark
        case .codex: return "BrandCodex"       // OpenAI mark
        }
    }

    private var tint: Color {
        switch id {
        case .claudeCode: return Color(red: 0.85, green: 0.47, blue: 0.34) // Claude clay
        case .codex: return Color(red: 0.04, green: 0.64, blue: 0.50)      // OpenAI green
        }
    }
}
