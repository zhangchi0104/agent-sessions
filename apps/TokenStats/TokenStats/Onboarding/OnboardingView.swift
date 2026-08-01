//
//  OnboardingView.swift
//  TokenStats
//
//  The first-run onboarding card, hosted in its own window (see
//  OnboardingWindowController). This file is the chrome and the navigation:
//  the header, the step order, and Back/Continue. Each step is its own file —
//  a disclosure of what TokenStats accesses, connecting the Coding Agents
//  (reusing UsageModel's sign-in flows), and a wrap-up summary. Every step is
//  skippable.
//

import SwiftUI

struct OnboardingView: View {
    let model: UsageModel
    /// Closes the hosting window. Dismissal is what records "onboarding done"
    /// (the window controller flips the persisted flag), so Skip and Finish both
    /// just call this.
    let onClose: () -> Void

    @State private var step: Step = .disclosure

    /// The ordered steps. `rawValue` drives Back/Continue and the step indicator.
    /// The disclosure leads so the user reads what TokenStats accesses before the
    /// one sensitive action, signing in.
    enum Step: Int, CaseIterable {
        case disclosure, accounts, done

        /// The adjacent steps, or nil at the ends — keeps the index arithmetic
        /// out of the navigation callsites.
        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 600)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(OnboardingCopy.welcomeTitle)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("onboarding.welcome.title")
            StepIndicator(current: step)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var footer: some View {
        HStack {
            Button(action: onClose) {
                Text(OnboardingCopy.skipButton)
            }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            if step.previous != nil {
                Button(action: back) {
                    Text(OnboardingCopy.backButton)
                }
            }
            Button(action: next) {
                Text(step == .done ? OnboardingCopy.finishButton : OnboardingCopy.continueButton)
            }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .disclosure: OnboardingDisclosureStep()
        case .accounts: OnboardingAccountsStep(model: model)
        case .done: OnboardingDoneStep(model: model)
        }
    }

    private func next() {
        if let nextStep = step.next {
            withAnimation(.snappy(duration: 0.25)) { step = nextStep }
        } else {
            onClose()
        }
    }

    private func back() {
        if let prevStep = step.previous {
            withAnimation(.snappy(duration: 0.25)) { step = prevStep }
        }
    }
}

/// The progress indicator under the title: one segment per step, filled up to
/// and including the current step, with the current segment widened.
private struct StepIndicator: View {
    let current: OnboardingView.Step

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingView.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue
                          ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: step == current ? 26 : 18, height: 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: current)
    }
}

/// The title-and-subtitle pair that opens a step's content.
struct OnboardingStepHeading: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    init(_ title: LocalizedStringResource, _ subtitle: LocalizedStringResource) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum OnboardingCopy {
    static let welcomeTitle = LocalizedStringResource.onboardingWelcomeTitle

    static let skipButton = LocalizedStringResource.onboardingNavigationSkipButton

    static let backButton = LocalizedStringResource.onboardingNavigationBackButton

    static let continueButton = LocalizedStringResource.onboardingNavigationContinueButton

    static let finishButton = LocalizedStringResource.onboardingNavigationFinishButton
}
