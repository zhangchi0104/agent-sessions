//
//  OnboardingDisclosureStep.swift
//  TokenStats
//
//  Onboarding step 1. What the upcoming sensitive step touches — shown before
//  any sign-in so the user consents with eyes open. Mirrors the privacy stance
//  stated in the Settings Subscriptions pane.
//

import SwiftUI

struct OnboardingDisclosureStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeading(DisclosureCopy.title, DisclosureCopy.subtitle)
            VStack(alignment: .leading, spacing: 14) {
                row("key.fill", DisclosureCopy.keychainTitle, DisclosureCopy.keychainDetail)
                row("network", DisclosureCopy.providersTitle, DisclosureCopy.providersDetail)
                row("internaldrive.fill", DisclosureCopy.localWorkTitle, DisclosureCopy.localWorkDetail)
            }
            Text(DisclosureCopy.optionalFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ icon: String,
                     _ title: LocalizedStringResource,
                     _ detail: LocalizedStringResource) -> some View {
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

private enum DisclosureCopy {
    static let title = LocalizedStringResource.onboardingDisclosureTitle

    static let subtitle = LocalizedStringResource.onboardingDisclosureSubtitle

    static let keychainTitle = LocalizedStringResource.onboardingDisclosureKeychainTitle

    static let keychainDetail = LocalizedStringResource.onboardingDisclosureKeychainDetail

    static let providersTitle = LocalizedStringResource.onboardingDisclosureProvidersTitle

    static let providersDetail = LocalizedStringResource.onboardingDisclosureProvidersDetail

    static let localWorkTitle = LocalizedStringResource.onboardingDisclosureLocalWorkTitle

    static let localWorkDetail = LocalizedStringResource.onboardingDisclosureLocalWorkDetail

    static let optionalFooter = LocalizedStringResource.onboardingDisclosureOptionalFooter
}
