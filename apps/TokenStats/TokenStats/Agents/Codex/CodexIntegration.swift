//
//  CodexIntegration.swift
//  TokenStats
//
//  Codex's entry in the Coding Agent registry: every fact the rest of the app
//  needs about it, declared once.
//

import SwiftUI

struct CodexIntegration: CodingAgentIntegration {
    let id: CodingAgentID = .codex
    let displayName = "Codex"
    let shortLabel = "X"
    let brand = AgentBrand(assetName: "BrandCodex",                          // OpenAI mark
                           tint: Color(red: 0.04, green: 0.64, blue: 0.50))  // OpenAI green
    let signInStyle: SignInStyle = .selfCompleting

    /// Two equal windows, no per-model meter. Sized as a deliberate two-up
    /// pair, not Claude's three-slot row with the center missing: equal dials
    /// larger than Claude's side dials, with wide spacing, centered in the
    /// popover's 300pt content width (96+32+96 = 224).
    let gaugeLayout = GaugeLayout(
        slots: [.init(label: "5-hour"), .init(label: "Weekly")],
        sizing: GaugeSizing(sideDiameter: 96, centerDiameter: 96,
                            sideLineWidth: 6, centerLineWidth: 6, circularSpacing: 32)
    )

    var transcriptRoot: String { realHomeDirectory() + "/.codex/sessions" }

    let auth: any AgentAuthSession

    init(auth: any AgentAuthSession = CodexAuthSession()) {
        self.auth = auth
    }

    func makeProvider() -> UsageProvider {
        CodexUsageProvider(
            accessToken: { [auth] in try await auth.validAccessToken() },
            accountID: { [auth] in auth.accountID() }
        )
    }
}
