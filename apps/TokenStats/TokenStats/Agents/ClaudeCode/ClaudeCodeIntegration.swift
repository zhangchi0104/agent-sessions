//
//  ClaudeCodeIntegration.swift
//  TokenStats
//
//  Claude Code's entry in the Coding Agent registry: every fact the rest of the
//  app needs about it, declared once.
//

import SwiftUI

struct ClaudeCodeIntegration: CodingAgentIntegration {
    let id: CodingAgentID = .claudeCode
    let displayName = "Claude Code"
    let shortLabel = "C"
    let brand = AgentBrand(assetName: "BrandClaude",                          // Anthropic / Claude spark
                           tint: Color(red: 0.85, green: 0.47, blue: 0.34))   // Claude clay
    let signInStyle: SignInStyle = .pasteCode

    /// Three windows — weekly (left), the 5-hour "session limit" emphasized in
    /// the center, and the weekly Fable limit (right).
    let gaugeLayout = GaugeLayout(slots: [
        .init(identity: .weekly),
        .init(identity: .shortTerm, emphasized: true),
        .init(identity: .modelWeekly(model: "Fable")),
    ])

    var transcriptRoot: String { realHomeDirectory() + "/.claude/projects" }

    let auth: any AgentAuthSession

    init(auth: any AgentAuthSession = ClaudeCodeAuthSession()) {
        self.auth = auth
    }

    func makeProvider() -> UsageProvider {
        ClaudeCodeUsageProvider(accessToken: { [auth] in try await auth.validAccessToken() })
    }
}
