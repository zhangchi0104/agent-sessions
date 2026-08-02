//
//  OnboardingDoneStep.swift
//  TokenStats
//
//  Onboarding step 3: a wrap-up of what the user just set up, and where the app
//  lives from here on.
//

import SwiftUI

struct OnboardingDoneStep: View {
    let model: UsageModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text(DoneCopy.title).font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 12) {
                summaryRow(connectedCount > 0 ? "checkmark.circle.fill" : "exclamationmark.circle",
                           connectedCount > 0 ? .green : .orange,
                           connectedCount > 0
                               ? DoneCopy.connectedAgents(
                                   connectedCount: connectedCount,
                                   totalCount: CodingAgentID.allCases.count.formatted(
                                       .number.locale(locale)
                                   )
                               )
                               : DoneCopy.noConnectedAgents)
                summaryRow("star.circle.fill", .accentColor,
                           DoneCopy.primaryAgent(model.appearance.primaryAgent.integration.displayName))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(DoneCopy.footer)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectedCount: Int {
        CodingAgentID.allCases.filter { model.agentStates[$0] != .signedOut }.count
    }

    private func summaryRow(_ icon: String,
                            _ color: Color,
                            _ text: LocalizedStringResource) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
    }
}

private enum DoneCopy {
    static let title = LocalizedStringResource.onboardingDoneTitle

    static func connectedAgents(connectedCount: Int, totalCount: String) -> LocalizedStringResource {
        LocalizedStringResource.onboardingDoneConnectedAgentsSummary(connectedCount, totalCount)
    }

    static let noConnectedAgents = LocalizedStringResource.onboardingDoneNoConnectedAgentsSummary

    static func primaryAgent(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.onboardingDonePrimaryAgentSummary(agentName)
    }

    static let footer = LocalizedStringResource.onboardingDoneFooter
}
