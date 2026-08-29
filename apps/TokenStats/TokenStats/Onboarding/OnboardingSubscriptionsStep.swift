//
//  OnboardingSubscriptionsStep.swift
//  TokenStats
//
//  Onboarding step 2. Connects the Coding Agents and picks the primary
//  subscription, driving the same UsageModel sign-in flows the Settings
//  Subscriptions pane uses — so progress here shows up everywhere.
//

import SwiftUI

struct OnboardingSubscriptionsStep: View {
    let model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeading(
                OnboardingSubscriptionsCopy.title,
                OnboardingSubscriptionsCopy.subtitle
            )
            VStack(spacing: 12) {
                ForEach(CodingAgentID.allCases, id: \.self) { id in
                    OnboardingSubscriptionRow(model: model, id: id)
                }
            }
            primaryPicker
        }
    }

    private var primaryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(OnboardingSubscriptionsCopy.primarySubscriptionTitle)
                .font(.callout.weight(.semibold))
            Picker(selection: Binding(
                get: { model.appearance.primaryAgent },
                set: { model.appearance.primaryAgent = $0 })) {
                ForEach(CodingAgentID.allCases, id: \.self) { id in
                    Text(id.integration.displayName).tag(id)
                }
            } label: {
                Text(OnboardingSubscriptionsCopy.primarySubscriptionTitle)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(OnboardingSubscriptionsCopy.primarySubscriptionFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

private enum OnboardingSubscriptionsCopy {
    static let title = LocalizedStringResource.onboardingSubscriptionsTitle

    static let subtitle = LocalizedStringResource.onboardingSubscriptionsSubtitle

    static let primarySubscriptionTitle = LocalizedStringResource.onboardingSubscriptionsPrimarySubscriptionTitle

    static let primarySubscriptionFooter = LocalizedStringResource.onboardingSubscriptionsPrimarySubscriptionFooter
}

/// One agent's connect tile: identity, status, and the state-dependent sign-in
/// controls.
private struct OnboardingSubscriptionRow: View {
    let model: UsageModel
    let id: CodingAgentID

    private var sessionState: SessionState { model.sessionStates[id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AgentIconBadge(id: id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.integration.displayName).font(.body.weight(.semibold))
                    ConnectionStatusLabel(status: ConnectionStatus(sessionState: sessionState,
                                                                   awaitingCode: model.isAwaitingCode(id),
                                                                   signingIn: model.isSigningIn(id)),
                                          font: .caption, style: .tintedText)
                }
                Spacer(minLength: 0)
                trailing
            }

            if SessionPresentation.showsSignInControls(
                sessionState,
                awaitingCode: model.isAwaitingCode(id)
            ) {
                AgentSignInControls(model: model, id: id, font: .caption)
            }

            if let error = model.loginError[id] {
                ErrorDiagnosticsDisclosure(
                    summary: error,
                    diagnostics: model.diagnostics[id],
                    font: .caption
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var trailing: some View {
        if model.isRefreshing(id) || model.isSigningIn(id)
            || SessionPresentation.isChecking(sessionState) {
            ProgressView().controlSize(.small)
        } else if SessionPresentation.isVerified(sessionState) {
            Image(systemName: "checkmark.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.green)
        } else if SessionPresentation.isTemporarilyUnverifiable(sessionState) {
            Button(LocalizedStringResource.settingsSubscriptionsRetryVerificationButton) {
                model.refreshManually(id)
            }
            .disabled(model.isRefreshing(id))
        }
    }
}
