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

    /// Codex windows are duration-named and rendered dynamically because the
    /// endpoint may expose only a weekly window. Empty fixed slots mean no
    /// invented 5-hour placeholder; if a real short window returns later, the
    /// parser supplies it and the same layout displays it automatically.
    let gaugeLayout = GaugeLayout(
        slots: [],
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
