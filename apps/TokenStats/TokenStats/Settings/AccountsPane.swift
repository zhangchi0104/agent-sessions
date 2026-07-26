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
            ForEach(model.appearance.displayOrder, id: \.self) { id in
                AccountSection(model: model, id: id)
            }

            // Descriptive copy reads as a caption below the account tiles
            // (a footer renders as plain secondary text), so it no longer
            // competes with the tappable account cards above it.
            Section {} footer: {
                Text("TokenStats stores each account's tokens in your Keychain "
                     + "and never sends them anywhere else.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accounts")
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
                        Button("Sign out", role: .destructive) { model.signOut(id) }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    AgentIconBadge(id: id)
                    Text(id.displayName).font(.headline)
                }
            }

            if !isConnected {
                AgentSignInControls(model: model, id: id, font: .callout)
            }

            if let error = model.loginError[id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var isConnected: Bool { model.agentStates[id] != .signedOut }

    private var status: ConnectionStatus { ConnectionStatus(model: model, id: id) }
}
