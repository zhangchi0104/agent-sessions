//
//  OnboardingAccountsStep.swift
//  TokenStats
//
//  Onboarding step 2. Connects the Coding Agents and picks the primary
//  subscription, driving the same UsageModel sign-in flows the Settings
//  Accounts pane uses — so progress here shows up everywhere.
//

import SwiftUI

struct OnboardingAccountsStep: View {
    let model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeading("Connect your agents",
                                  "Sign in so TokenStats can read your usage. Connect one or both — "
                                  + "or skip and do it later in Settings.")
            VStack(spacing: 12) {
                ForEach(CodingAgentID.allCases, id: \.self) { id in
                    OnboardingAccountRow(model: model, id: id)
                }
            }
            primaryPicker
        }
    }

    private var primaryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Primary subscription").font(.callout.weight(.semibold))
            Picker("Primary subscription", selection: Binding(
                get: { model.appearance.primaryAgent },
                set: { model.appearance.primaryAgent = $0 })) {
                ForEach(CodingAgentID.allCases, id: \.self) { id in
                    Text(id.integration.displayName).tag(id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Shown first and badged in the popover and menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

/// One agent's connect tile: identity, status, and the state-dependent sign-in
/// controls.
private struct OnboardingAccountRow: View {
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
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
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
