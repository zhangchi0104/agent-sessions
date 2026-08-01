//
//  AccountsPane.swift
//  TokenStats
//
//  Settings → Accounts: connect or disconnect each Coding Agent and run the
//  sign-in flows. Tokens are stored in TokenStats' own Keychain item (see
//  docs/claude-code-integration.md).
//

import SwiftUI

/// Account management: connect or disconnect each Coding Agent.
struct AccountsPane: View {
    let model: UsageModel

    var body: some View {
        Form {
            // Accounts remains an unfiltered management surface: hiding an
            // agent elsewhere must never hide the controls needed to sign in
            // again or turn that agent's presentation back on.
            ForEach(model.appearance.displayOrder, id: \.self) { id in
                AccountSection(model: model, id: id)
            }

            // Descriptive copy reads as a caption below the account tiles
            // (a footer renders as plain secondary text), so it no longer
            // competes with the tappable account cards above it.
            Section {} footer: {
                Text(AccountsCopy.keychainPrivacyFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(AccountsCopy.title))
    }
}

/// One Coding Agent's account block: a status row plus the state-dependent
/// connect / disconnect controls and any sign-in error.
private struct AccountSection: View {
    let model: UsageModel
    let id: CodingAgentID

    var body: some View {
        Section {
            // Header row: agent name on the left; status + (when connected)
            // the Sign-out control share the trailing edge so a connected
            // account reads as one compact row instead of a status line with
            // a button stranded on a near-empty row beneath it.
            LabeledContent {
                HStack(spacing: 10) {
                    if model.isRefreshing(id) {
                        ProgressView().controlSize(.small)
                    }
                    ConnectionStatusLabel(status: status)
                    if isConnected {
                        Button(role: .destructive, action: { model.signOut(id) }) {
                            Text(AccountsCopy.signOutButton)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    AgentIconBadge(id: id)
                    Text(id.integration.displayName).font(.headline)
                }
            }

            if !isConnected {
                AgentSignInControls(model: model, id: id, font: .callout)
            }

            if let error = model.loginError[id] {
                ErrorDiagnosticsDisclosure(
                    summary: error,
                    diagnostics: model.diagnostics[id]
                )
            }
        }
    }

    private var isConnected: Bool { model.agentStates[id] != .signedOut }

    private var status: ConnectionStatus {
        ConnectionStatus(state: model.agentStates[id], awaitingCode: model.isAwaitingCode(id))
    }
}

private enum AccountsCopy {
    static let title = LocalizedStringResource.settingsAccountsTitle

    static let keychainPrivacyFooter = LocalizedStringResource.settingsAccountsKeychainPrivacyFooter

    static let signOutButton = LocalizedStringResource.settingsAccountsSignOutButton
}
