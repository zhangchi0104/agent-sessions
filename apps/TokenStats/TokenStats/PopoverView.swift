//
//  PopoverView.swift
//  TokenStats
//
//  The popover anchored to the menu-bar item: one section per Coding Agent
//  (Claude Code first, Codex second), each with its own Usage Windows,
//  last-updated / staleness line, sign-in, refresh, and account controls, plus
//  a shared Quit footer. All copy follows the glossary (Usage Window, never
//  "session"; full agent names in the popover).
//

import SwiftUI

struct PopoverView: View {
    let model: UsageModel
    @State private var pastedCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ForEach(Array(UsageModel.order.enumerated()), id: \.element) { index, id in
                if index > 0 { Divider() }
                AgentSection(model: model, id: id, pastedCode: $pastedCode)
            }

            Divider()
            HStack {
                Spacer()
                Button("Quit TokenStats") { model.quit() }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TokenStats").font(.headline)
            Spacer()
            Button {
                model.refreshAllManually()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh all")
        }
    }
}

/// One Coding Agent's section: name, state-dependent body, and its own
/// sign-in / refresh / account controls.
private struct AgentSection: View {
    let model: UsageModel
    let id: CodingAgentID
    @Binding var pastedCode: String

    private var displayName: String {
        switch id {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayName).font(.subheadline.weight(.semibold))
                Spacer()
                if model.isRefreshing(id) {
                    ProgressView().controlSize(.small)
                }
            }
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch model.agentStates[id] {
        case .signedOut:
            signedOut
        case .loading:
            if model.isRefreshing(id) {
                Text("Loading usage…").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Couldn't load usage.").font(.caption)
            }
            diagnostics
            signedInControls
        case .fresh(let snapshot):
            windows(snapshot)
            statusLine(text: "Updated \(UsageFormatting.relativeAge(of: snapshot.fetchedAt))",
                       isStale: false)
            signedInControls
        case .staleDisclosed(let snapshot):
            windows(snapshot)
            statusLine(text: "Couldn't refresh · last updated \(UsageFormatting.relativeAge(of: snapshot.fetchedAt))",
                       isStale: true)
            diagnostics
            signedInControls
        }
    }

    // MARK: - Signed out

    @ViewBuilder private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in to \(displayName) to see your Usage Windows.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch id {
            case .claudeCode:
                Button(model.isAwaitingCode ? "Re-open browser" : "Sign in to Claude Code") {
                    model.signInClaude()
                }
                if model.isAwaitingCode {
                    Text("Approve in your browser, then paste the code here:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Paste code", text: $pastedCode)
                            .textFieldStyle(.roundedBorder)
                        Button("Submit") {
                            model.submitPastedCode(pastedCode)
                            pastedCode = ""
                        }
                        .disabled(pastedCode.isEmpty)
                    }
                }
            case .codex:
                Button("Sign in to Codex") { model.signInCodex() }
                Text("Approve in your browser; TokenStats finishes automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = model.loginError[id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Signed in

    private func windows(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                WindowRow(window: window)
            }
        }
    }

    private func statusLine(text: String, isStale: Bool) -> some View {
        HStack(spacing: 6) {
            if isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var diagnostics: some View {
        if let diagnostics = model.diagnostics[id] {
            Text(diagnostics)
                .font(.caption2.monospaced())
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signedInControls: some View {
        HStack {
            Button {
                model.refreshManually(id)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing(id))

            Spacer()

            Menu("Account") {
                Button("Sign out") { model.signOut(id) }
            }
            .fixedSize()
        }
    }
}

/// One usage quota row: label, percent, bar, and reset/detail text.
private struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.label).font(.subheadline.weight(.medium))
                Spacer()
                Text(UsageFormatting.percentText(window.percentConsumed))
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: min(max(window.percentConsumed, 0), 100), total: 100)
                .tint(.primary)
            if let resetAt = window.resetAt {
                HStack {
                    Text(UsageFormatting.countdown(to: resetAt))
                    Spacer()
                    Text(UsageFormatting.absoluteTime(resetAt))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if let detailText = window.detailText {
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("reset time unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
