//
//  CursorIntegration.swift
//  TokenStats
//
//  Cursor's registry entry. Cursor supplies authoritative subscription
//  billing-cycle readings, but no compatible transcript source for the local
//  Token Odometer.
//

import SwiftUI

struct CursorIntegration: CodingAgentIntegration {
    let id: CodingAgentID = .cursor
    let displayName = "Cursor"
    let shortLabel = "R"
    let brand = AgentBrand(
        assetName: "BrandCursor",
        tint: Color(red: 0.36, green: 0.32, blue: 0.78)
    )
    let signInStyle: SignInStyle = .selfCompleting
    let gaugeLayout = GaugeLayout(
        slots: [],
        sizing: GaugeSizing(sideDiameter: 96, centerDiameter: 96,
                            sideLineWidth: 6, centerLineWidth: 6, circularSpacing: 32)
    )
    let transcriptRoot: String? = nil

    let auth: any AgentAuthSession

    init(auth: any AgentAuthSession = CursorAuthSession()) {
        self.auth = auth
    }

    func makeProvider() -> UsageProvider {
        CursorUsageProvider(accessToken: { [auth] in
            try await auth.validAccessToken()
        })
    }
}
