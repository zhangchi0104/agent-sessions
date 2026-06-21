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
import AppKit

struct OnboardingView: View {
    let model: UsageModel
    /// Closes the hosting window. Dismissal is what records "onboarding done"
    /// (the window controller flips the persisted flag), so Skip and Finish both
    /// just call this.
    let onClose: () -> Void

    @State private var step: Step = .disclosure
    @State private var hooksDetected = false

    /// The ordered steps. `rawValue` drives Back/Continue and the step indicator.
    /// The disclosure leads so the user reads what TokenStats accesses before any
    /// sensitive action (signing in, installing hooks).
    enum Step: Int, CaseIterable {
        case disclosure, accounts, hooks, done

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
        // Poll for the sessions database the hook plugin writes to. Its presence
        // is the signal that tracking is live; cheap enough to check every 2s
        // while the window is open, and it keeps the banner + summary current.
        .task {
            while !Task.isCancelled {
                hooksDetected = FileManager.default.fileExists(
                    atPath: SessionStore.resolveDatabasePath())
                try? await Task.sleep(for: .seconds(2))
            }
        }
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
        case .disclosure: disclosureStep
        case .accounts: accountsStep
        case .hooks: hooksStep
        case .done: doneStep
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

    // MARK: - Step 1: Disclosure

    /// What the upcoming sensitive steps touch — shown before any sign-in or
    /// hook install so the user consents with eyes open. Mirrors the privacy
    /// stance stated in the Settings Accounts pane.
    private var disclosureStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading("Before you start",
                        "The next steps connect your accounts and turn on tracking. Here's "
                        + "exactly what TokenStats accesses — and what it never does.")
            VStack(alignment: .leading, spacing: 14) {
                disclosureRow("key.fill", "Tokens stay in your Keychain",
                              "Signing in opens your browser to approve TokenStats. The access "
                              + "tokens are saved in your macOS Keychain and used only to read your usage.")
                disclosureRow("network", "Only your providers are contacted",
                              "Usage is fetched directly from Claude and OpenAI. Your tokens and "
                              + "usage are never sent to any other server.")
                disclosureRow("internaldrive.fill", "Tracking data never leaves your Mac",
                              "The optional hook plugin records session activity to a local database "
                              + "on this Mac that only TokenStats reads.")
            }
            Text("Every step is optional — you can skip any of them and change these later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func disclosureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
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

    // MARK: - Step 2: Accounts

    private var accountsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading("Connect your agents",
                        "Sign in so TokenStats can read your usage. Connect one or both — "
                        + "or skip and do it later in Settings.")
            VStack(spacing: 12) {
                OnboardingAccountRow(model: model, id: .claudeCode)
                OnboardingAccountRow(model: model, id: .codex)
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
                    Text(id.displayName).tag(id)
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

    // MARK: - Step 3: Hooks

    private var hooksStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading("Enable live tracking",
                        "Real-time session and token tracking comes from a small hook "
                        + "plugin that records activity to a database TokenStats reads. "
                        + "Install it in your agent with the commands below.")
            detectionBanner
            CommandBlock(
                title: "Claude Code",
                subtitle: "Run in a Claude Code session:",
                command: "/plugin marketplace add https://github.com/zhangchi0104/agent-sessions.git#release\n"
                    + "/plugin install claude-session-event-writer@agent-sessions")
            CommandBlock(
                title: "Codex",
                subtitle: "Add to your Codex config (replace the path with your checkout):",
                command: """
                [marketplaces.agent-sessions]
                source_type = "local"
                source = "/path/to/agent-sessions"

                [plugins."codex-session-event-writer@agent-sessions"]
                enabled = true
                """)
            Text("Requires bun on your PATH. You can skip this and set it up later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detectionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: hooksDetected ? "checkmark.circle.fill" : "clock.badge.questionmark")
                .imageScale(.large)
                .foregroundStyle(hooksDetected ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(hooksDetected ? "Hooks detected — tracking is live"
                                   : "Waiting for the first tracked event…")
                    .font(.callout.weight(.medium))
                if !hooksDetected {
                    Text("Run a prompt in your agent after installing; this updates automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background((hooksDetected ? Color.green : Color.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Step 4: Done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("You're all set").font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 12) {
                summaryRow(connectedCount > 0 ? "checkmark.circle.fill" : "exclamationmark.circle",
                           connectedCount > 0 ? .green : .orange,
                           connectedCount > 0 ? "\(connectedCount) of \(CodingAgentID.allCases.count) agents connected"
                                              : "No agents connected yet")
                summaryRow("star.circle.fill", .accentColor,
                           "Primary: \(model.appearance.primaryAgent.displayName)")
                summaryRow(hooksDetected ? "checkmark.circle.fill" : "clock",
                           hooksDetected ? .green : .orange,
                           hooksDetected ? "Live tracking active" : "Live tracking not detected yet")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("TokenStats lives in your menu bar. You can reconnect agents or revisit "
                 + "this setup anytime from Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectedCount: Int {
        CodingAgentID.allCases.filter { model.agentStates[$0] != .signedOut }.count
    }

    private func summaryRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared

    private func stepHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

/// One agent's connect tile in the onboarding flow: identity, status, and the
/// state-dependent sign-in controls. Drives the same UsageModel sign-in methods
/// the Settings Accounts pane uses, so progress here shows up everywhere.
private struct OnboardingAccountRow: View {
    let model: UsageModel
    let id: CodingAgentID
    @State private var pastedCode = ""

    private var isConnected: Bool { model.agentStates[id] != .signedOut }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AgentIconBadge(id: id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.displayName).font(.body.weight(.semibold))
                    statusLine
                }
                Spacer(minLength: 0)
                trailing
            }

            if !isConnected { signInControls }

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

    @ViewBuilder private var statusLine: some View {
        if isConnected {
            Text("Connected").font(.caption).foregroundStyle(.green)
        } else if id == .claudeCode && model.isAwaitingCode {
            Text("Awaiting code").font(.caption).foregroundStyle(.orange)
        } else {
            Text("Not signed in").font(.caption).foregroundStyle(.secondary)
        }
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

    @ViewBuilder private var signInControls: some View {
        switch id {
        case .claudeCode:
            Button(model.isAwaitingCode ? "Re-open browser" : "Sign in to Claude Code") {
                model.signInClaude()
            }
            if model.isAwaitingCode {
                Text("Approve TokenStats in your browser, then paste the code here:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Paste code", text: $pastedCode)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                    Button("Submit", action: submit).disabled(pastedCode.isEmpty)
                }
            }
        case .codex:
            Button("Sign in to Codex") { model.signInCodex() }
            Text("Approve in your browser; TokenStats finishes automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        guard !pastedCode.isEmpty else { return }
        model.submitPastedCode(pastedCode)
        pastedCode = ""
    }
}

/// A titled, copyable command snippet. The Copy button latches to a "Copied"
/// confirmation so the user gets feedback that the clipboard was written.
private struct CommandBlock: View {
    let title: String
    let subtitle: String
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.black.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
    }
}
