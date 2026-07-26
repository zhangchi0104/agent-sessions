//
//  OnboardingView.swift
//  TokenStats
//
//  The first-run onboarding dialog: a three-step card hosted in its own window
//  (see OnboardingWindowController). Step 1 connects the Coding Agents and picks
//  the primary subscription (reusing UsageModel's sign-in flows). Step 2 guides
//  the user to install the live-tracking hook plugin — TokenStats can't install
//  it (it's a Claude Code / Codex plugin), so we show the copyable commands and
//  watch for the shared sessions database to appear as proof the hooks fired.
//  Step 3 is a wrap-up summary. Every step is skippable.
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
            Text("Welcome to TokenStats")
                .font(.title2.weight(.semibold))
            StepIndicator(current: step)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var footer: some View {
        HStack {
            Button("Skip", action: onClose)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            if step.previous != nil {
                Button("Back", action: back)
            }
            Button(step == .done ? "Finish" : "Continue", action: next)
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

/// The three-segment progress indicator under the title: filled up to and
/// including the current step, with the current segment widened.
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
    let title: String
    let subtitle: String

    init(_ title: String, _ subtitle: String) {
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
