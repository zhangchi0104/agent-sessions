//
//  OnboardingDisclosureStep.swift
//  TokenStats
//
//  Onboarding step 1. What the upcoming sensitive step touches — shown before
//  any sign-in so the user consents with eyes open. Mirrors the privacy stance
//  stated in the Settings Accounts pane.
//

import SwiftUI

struct OnboardingDisclosureStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeading("Before you start",
                                  "The next step connects your accounts. Here's exactly what "
                                  + "TokenStats accesses — and what it never does.")
            VStack(alignment: .leading, spacing: 14) {
                row("key.fill", "Tokens stay in your Keychain",
                    "Signing in opens your browser to approve TokenStats. The access "
                    + "tokens are saved in your macOS Keychain and used only to read your usage.")
                row("network", "Usage and public exchange rates",
                    "Usage is fetched directly from Claude and OpenAI. TokenStats can "
                    + "automatically request a public USD exchange-rate table at most "
                    + "once every 24 hours. Frankfurter is the default; Settings lets "
                    + "you choose one supported HTTPS service and endpoint. TokenStats "
                    + "contacts only that selection and never fails over automatically. "
                    + "TokenStats adds no account, token, usage, transcript, calculated cost, "
                    + "or region data. The selected host receives the configured URL path and "
                    + "query plus ordinary connection metadata, so never put credentials "
                    + "or API keys in the URL.")
                row("internaldrive.fill", "Nothing about your work leaves your Mac",
                    "Your token counts are read from your agents' transcript files "
                    + "on this Mac. TokenStats reads them and uploads nothing.")
            }
            Text("Every step is optional — you can skip any of them and change these later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
