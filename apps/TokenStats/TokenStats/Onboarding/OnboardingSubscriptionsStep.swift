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

    private var isConnected: Bool { model.agentStates[id] != .signedOut }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AgentIconBadge(id: id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.integration.displayName).font(.body.weight(.semibold))
                    ConnectionStatusLabel(status: ConnectionStatus(state: model.agentStates[id],
                                                                   awaitingCode: model.isAwaitingCode(id)),
                                          font: .caption, style: .tintedText)
                }
                Spacer(minLength: 0)
                trailing
            }

            if !isConnected {
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
        if model.isRefreshing(id) {
            ProgressView().controlSize(.small)
        } else if isConnected {
            Image(systemName: "checkmark.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.green)
        }
    }
}
