//
//  PopoverView.swift
//  TokenStats
//
//  The popover anchored to the menu-bar item: one section per Coding Agent
//  (Claude Code first, Codex second), each with its own Usage Windows,
//  last-updated / staleness line, and sign-in flow, plus a single
//  Settings control in the footer that manages every account (sign in / sign
//  out per agent), a global refresh control, and Quit. All copy follows the
//  glossary (Usage Window, never "session"; full agent names in the popover).
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
                settings
            }
        }
        .padding(14)
        .frame(width: 308)
    }

    /// The single account-management control: one entry per Coding Agent that
    /// signs that agent in or out depending on its state, plus Quit.
    private var settings: some View {
        Menu {
            ForEach(Array(UsageModel.order.enumerated()), id: \.element) { _, id in
                Section(displayName(for: id)) {
                    if model.agentStates[id] == .signedOut {
                        Button("Sign in") { signIn(id) }
                    } else {
                        Button("Sign out") { model.signOut(id) }
                    }
                }
            }

            Divider()
            Button("Quit TokenStats") { model.quit() }
        } label: {
            Image(systemName: "gearshape")
                .imageScale(.large)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    private func displayName(for id: CodingAgentID) -> String {
        switch id {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    private func signIn(_ id: CodingAgentID) {
        switch id {
        case .claudeCode: model.signInClaude()
        case .codex: model.signInCodex()
        }
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

/// One Coding Agent's section: name, state-dependent body, and sign-in flow.
private struct AgentSection: View {
    let model: UsageModel
    let id: CodingAgentID
    @Binding var pastedCode: String
    @State private var isDiagnosticsPopoverPresented = false

    private var displayName: String {
        switch id {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                statusLine(text: "Couldn't load usage.",
                           isStale: true,
                           diagnostics: model.diagnostics[id])
            }
        case .fresh(let snapshot):
            windows(snapshot)
            statusLine(text: "Updated \(UsageFormatting.relativeAge(of: snapshot.fetchedAt))",
                       isStale: false)
        case .staleDisclosed(let snapshot):
            windows(snapshot)
            statusLine(text: "Couldn't refresh · last updated \(UsageFormatting.relativeAge(of: snapshot.fetchedAt))",
                       isStale: true,
                       diagnostics: model.diagnostics[id])
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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(Array(visibleWindows(in: snapshot).enumerated()), id: \.offset) { _, window in
                WindowTile(window: window)
            }
        }
    }

    private func visibleWindows(in snapshot: UsageSnapshot) -> [UsageWindow] {
        snapshot.windows.filter { window in
            window.label == "5-hour" || window.label == "Weekly"
        }
    }

    @ViewBuilder private func statusLine(text: String,
                                         isStale: Bool,
                                         diagnostics: String? = nil) -> some View {
        if let diagnostics, diagnostics.isEmpty == false {
            Button {
                isDiagnosticsPopoverPresented = true
            } label: {
                StatusLineContent(text: text, isStale: isStale, showsDetailsIndicator: true)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Show error details")
            .accessibilityLabel("\(text). Show error details")
            .popover(isPresented: $isDiagnosticsPopoverPresented, arrowEdge: .bottom) {
                DiagnosticsPopover(diagnostics: diagnostics)
            }
        } else {
            StatusLineContent(text: text, isStale: isStale, showsDetailsIndicator: false)
        }
    }
}

private struct StatusLineContent: View {
    let text: String
    let isStale: Bool
    let showsDetailsIndicator: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if showsDetailsIndicator {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct DiagnosticsPopover: View {
    let diagnostics: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error details")
                .font(.caption.weight(.semibold))

            ScrollView {
                Text(diagnostics)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 300)
            .frame(maxHeight: 180)
        }
        .padding(12)
    }
}

/// One compact square usage quota tile: title/countdown header and percentage ring.
private struct WindowTile: View {
    let window: UsageWindow

    var body: some View {
        ZStack {
            PercentRing(percent: window.percentConsumed, centerText: UsageFormatting.percentText(window.percentConsumed))
                .frame(width: 84, height: 84)
                .offset(y: ringVerticalOffset)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(window.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if let headerAccessoryText {
                        Text(headerAccessoryText)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.028))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.075), lineWidth: 1)
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var headerAccessoryText: String? {
        if let resetAt = window.resetAt {
            return UsageFormatting.timerText(to: resetAt)
        }
        return "-"
    }

    private var ringVerticalOffset: CGFloat {
        10
    }

    private var helpText: String {
        if let resetAt = window.resetAt {
            return "\(window.label), \(UsageFormatting.percentText(window.percentConsumed)), resets at \(UsageFormatting.absoluteTime(resetAt))"
        }
        return "\(window.label), \(UsageFormatting.percentText(window.percentConsumed)), reset unavailable"
    }

    private var accessibilityText: String {
        if let resetAt = window.resetAt {
            return "\(window.label), \(UsageFormatting.percentText(window.percentConsumed)), resets in \(UsageFormatting.timerText(to: resetAt))"
        }
        return "\(window.label), \(UsageFormatting.percentText(window.percentConsumed)), reset unavailable"
    }
}

private struct PercentRing: View {
    let percent: Double
    let centerText: String

    private var progress: Double {
        min(max(percent, 0), 100) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.11), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.primary,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(centerText)
                .font(.callout.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(6)
        }
        .accessibilityHidden(true)
    }
}
