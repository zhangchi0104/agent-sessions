//
//  SubscriptionsPane.swift
//  TokenStats
//
//  Settings → Subscriptions: connect or disconnect each Coding Agent and run the
//  sign-in flows. Tokens are stored in TokenStats' own Keychain item (see
//  docs/claude-code-integration.md).
//

import SwiftUI

/// Subscription management: connect or disconnect each Coding Agent.
struct SubscriptionsPane: View {
    let model: UsageModel
    @State private var pendingSubscriptions: Set<CodingAgentID> = []

    var body: some View {
        Form {
            ForEach(displayedSubscriptions, id: \.self) { id in
                SubscriptionSection(model: model, id: id) {
                    pendingSubscriptions.remove(id)
                    model.signOut(id)
                }
            }

            // Descriptive copy reads as a caption below the subscription tiles
            // (a footer renders as plain secondary text), so it no longer
            // competes with the tappable subscription cards above it.
            Section {} footer: {
                Text(SubscriptionsCopy.keychainPrivacyFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(SubscriptionsCopy.title))
        .overlay {
            if displayedSubscriptions.isEmpty {
                ContentUnavailableView(
                    SubscriptionsCopy.emptyTitle,
                    systemImage: "creditcard",
                    description: Text(SubscriptionsCopy.emptyDescription)
                )
                .padding(.horizontal, 48)
                .padding(.bottom, 44)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            addSubscriptionMenu
                .padding(.trailing, 20)
                .padding(.bottom, 16)
        }
    }

    private var displayedSubscriptions: [CodingAgentID] {
        SubscriptionListPresentation.displayedSubscriptions(
            in: model.appearance.displayOrder,
            states: model.sessionStates,
            pending: pendingSubscriptions
        )
    }

    private var availableSubscriptions: [CodingAgentID] {
        SubscriptionListPresentation.availableSubscriptions(
            in: model.appearance.displayOrder,
            states: model.sessionStates,
            pending: pendingSubscriptions
        )
    }

    private var addSubscriptionMenu: some View {
        Menu {
            ForEach(availableSubscriptions, id: \.self) { id in
                Button {
                    pendingSubscriptions.insert(id)
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
        .disabled(availableSubscriptions.isEmpty)
        .accessibilityLabel(SubscriptionsCopy.addSubscriptionButton)
        .accessibilityIdentifier("settings.subscriptions.add")
        .help(SubscriptionsCopy.addSubscriptionButton)
    }
}

/// Resolves the visible subscription rows and add menu from the same set, so a
/// subscription can never appear in both places or be added twice.
enum SubscriptionListPresentation {
    static func displayedSubscriptions(
        in displayOrder: [CodingAgentID],
        states: CodingAgentSessionStates,
        pending: Set<CodingAgentID>
    ) -> [CodingAgentID] {
        displayOrder.filter { pending.contains($0) || states.isPresent($0) }
    }

    static func availableSubscriptions(
        in displayOrder: [CodingAgentID],
        states: CodingAgentSessionStates,
        pending: Set<CodingAgentID>
    ) -> [CodingAgentID] {
        let displayed = Set(displayedSubscriptions(
            in: displayOrder,
            states: states,
            pending: pending
        ))
        return displayOrder.filter { !displayed.contains($0) }
    }
}

/// One Coding Agent's subscription block: a verified session status plus the
/// state-dependent recovery / disconnect controls and any sign-in error.
private struct SubscriptionSection: View {
    let model: UsageModel
    let id: CodingAgentID
    let onSignOut: () -> Void

    var body: some View {
        Section {
            // Header row: agent name on the left; status + (when connected)
            // the Sign-out control share the trailing edge so a connected
            // subscription reads as one compact row instead of a status line with
            // a button stranded on a near-empty row beneath it.
            LabeledContent {
                HStack(spacing: 10) {
                    if model.isRefreshing(id) || model.isSigningIn(id) || model.isSigningOut(id)
                        || SessionPresentation.isChecking(sessionState) {
                        ProgressView().controlSize(.small)
                    }
                    ConnectionStatusLabel(status: status)
                    if SessionPresentation.isTemporarilyUnverifiable(sessionState) {
                        Button(SubscriptionsCopy.retryVerificationButton) {
                            model.refreshManually(id)
                        }
                        .disabled(model.isRefreshing(id))
                    }
                    if hasSubscription {
                        Button(role: .destructive, action: onSignOut) {
                            Text(SubscriptionsCopy.signOutButton)
                        }
                        .disabled(model.isSigningOut(id))
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    AgentIconBadge(id: id)
                    Text(id.integration.displayName).font(.headline)
                }
            }

            if SessionPresentation.showsSignInControls(
                sessionState,
                awaitingCode: model.isAwaitingCode(id)
            ) {
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

    private var sessionState: SessionState { model.sessionStates[id] }

    private var hasSubscription: Bool {
        SessionPresentation.keepsSubscriptionVisible(sessionState)
    }

    private var status: ConnectionStatus {
        ConnectionStatus(
            sessionState: sessionState,
            awaitingCode: model.isAwaitingCode(id),
            signingIn: model.isSigningIn(id)
        )
    }
}

private enum SubscriptionsCopy {
    static let title = LocalizedStringResource.settingsSubscriptionsTitle

    static let addSubscriptionButton = LocalizedStringResource.settingsSubscriptionsAddButton

    static let emptyTitle = LocalizedStringResource.settingsSubscriptionsEmptyTitle

    static let emptyDescription = LocalizedStringResource.settingsSubscriptionsEmptyDescription

    static let keychainPrivacyFooter = LocalizedStringResource.settingsSubscriptionsKeychainPrivacyFooter

    static let signOutButton = LocalizedStringResource.settingsSubscriptionsSignOutButton

    static let retryVerificationButton =
        LocalizedStringResource.settingsSubscriptionsRetryVerificationButton
}
