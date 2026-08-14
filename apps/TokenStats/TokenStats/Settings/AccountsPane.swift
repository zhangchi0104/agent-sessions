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
    @State private var pendingAccounts: Set<CodingAgentID> = []

    var body: some View {
        Form {
            ForEach(displayedAccounts, id: \.self) { id in
                AccountSection(model: model, id: id) {
                    pendingAccounts.remove(id)
                    model.signOut(id)
                }
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
        .overlay {
            if displayedAccounts.isEmpty {
                ContentUnavailableView(
                    AccountsCopy.emptyTitle,
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text(AccountsCopy.emptyDescription)
                )
                .padding(.horizontal, 48)
                .padding(.bottom, 44)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            addAccountMenu
                .padding(.trailing, 20)
                .padding(.bottom, 16)
        }
    }

    private var displayedAccounts: [CodingAgentID] {
        AccountListPresentation.displayedAccounts(
            in: model.appearance.displayOrder,
            states: model.agentStates,
            pending: pendingAccounts
        )
    }

    private var availableAccounts: [CodingAgentID] {
        AccountListPresentation.availableAccounts(
            in: model.appearance.displayOrder,
            states: model.agentStates,
            pending: pendingAccounts
        )
    }

    private var addAccountMenu: some View {
        Menu {
            ForEach(availableAccounts, id: \.self) { id in
                Button {
                    pendingAccounts.insert(id)
                    model.signIn(id)
                } label: {
                    Text(id.integration.displayName)
                }
            }
        } label: {
            Image(systemName: "plus")
                .frame(width: 24, height: 24)
        }
        .menuIndicator(.hidden)
        .disabled(availableAccounts.isEmpty)
        .accessibilityLabel(AccountsCopy.addAccountButton)
        .accessibilityIdentifier("settings.accounts.add")
        .help(AccountsCopy.addAccountButton)
    }
}

/// Resolves the visible account rows and the add menu from the same set, so an
/// account can never appear in both places or be added twice.
enum AccountListPresentation {
    static func displayedAccounts(
        in displayOrder: [CodingAgentID],
        states: CodingAgentStates,
        pending: Set<CodingAgentID>
    ) -> [CodingAgentID] {
        displayOrder.filter { pending.contains($0) || states.isConnected($0) }
    }

    static func availableAccounts(
        in displayOrder: [CodingAgentID],
        states: CodingAgentStates,
        pending: Set<CodingAgentID>
    ) -> [CodingAgentID] {
        let displayed = Set(displayedAccounts(in: displayOrder, states: states, pending: pending))
        return displayOrder.filter { !displayed.contains($0) }
    }
}

/// One Coding Agent's account block: a status row plus the state-dependent
/// connect / disconnect controls and any sign-in error.
private struct AccountSection: View {
    let model: UsageModel
    let id: CodingAgentID
    let onSignOut: () -> Void

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
                        Button(role: .destructive, action: onSignOut) {
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

    private var isConnected: Bool { model.agentStates.isConnected(id) }

    private var status: ConnectionStatus {
        ConnectionStatus(state: model.agentStates[id], awaitingCode: model.isAwaitingCode(id))
    }
}

private enum AccountsCopy {
    static let title = LocalizedStringResource.settingsAccountsTitle

    static let addAccountButton = LocalizedStringResource.settingsAccountsAddButton

    static let emptyTitle = LocalizedStringResource.settingsAccountsEmptyTitle

    static let emptyDescription = LocalizedStringResource.settingsAccountsEmptyDescription

    static let keychainPrivacyFooter = LocalizedStringResource.settingsAccountsKeychainPrivacyFooter

    static let signOutButton = LocalizedStringResource.settingsAccountsSignOutButton
}
