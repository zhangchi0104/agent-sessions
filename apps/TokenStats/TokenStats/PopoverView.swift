//
//  PopoverView.swift
//  TokenStats
//
//  The popover anchored to the menu-bar item: one section per Coding Agent
//  (in the user's Appearance order, primary first), each with its own Usage
//  Windows, last-updated / staleness line, and sign-in flow, plus a single
//  Settings control in the footer that manages every account (sign in / sign
//  out per agent), a global refresh control, and Quit. All copy follows the
//  glossary (Usage Window, never "session"; full agent names in the popover).
//

import SwiftUI
import AppKit

struct PopoverView: View {
    let model: UsageModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ForEach(Array(model.appearance.displayOrder.enumerated()), id: \.element) { index, id in
                if index > 0 { Divider() }
                AgentSection(model: model, id: id)
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

    /// Footer menu: open the dedicated Settings page (account management) or quit.
    private var settings: some View {
        Menu {
            Button("Settings…") { Self.openSettingsWindow(openWindow) }
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

    /// Open the Settings window and pull it to the front. The extra `activate`
    /// is needed because TokenStats is an LSUIElement (menu-bar-only) app, so
    /// its windows don't come forward — or take focus — on their own.
    static func openSettingsWindow(_ openWindow: OpenWindowAction) {
        openWindow(id: TokenStatsWindowID.settings)
        NSApp.activate(ignoringOtherApps: true)
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

/// A small "Primary" tag next to the primary agent's name (Appearance setting).
private struct PrimaryBadge: View {
    var body: some View {
        Text("Primary")
            .font(.system(size: 9, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .accessibilityLabel("Primary subscription")
    }
}

/// One Coding Agent's section: name, state-dependent body, and sign-in flow.
private struct AgentSection: View {
    let model: UsageModel
    let id: CodingAgentID
    @Environment(\.openWindow) private var openWindow
    @State private var isDiagnosticsPopoverPresented = false

    private var displayName: String { id.displayName }
    private var isPrimary: Bool { model.appearance.primaryAgent == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayName).font(.subheadline.weight(.semibold))
                if isPrimary { PrimaryBadge() }
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

    /// Signed-out agents stay lightweight in the popover: account management
    /// (and the sign-in flows) live on the dedicated Settings page.
    @ViewBuilder private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not signed in to \(displayName).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Sign in…") {
                PopoverView.openSettingsWindow(openWindow)
            }
            .controlSize(.small)
        }
    }

    // MARK: - Signed in

    @ViewBuilder private func windows(_ snapshot: UsageSnapshot) -> some View {
        let style = model.appearance.gaugeStyle
        switch id {
        case .claudeCode:
            // Weekly · 5-hour · credits, the 5-hour center-weighted.
            ClaudeGaugeCluster(snapshot: snapshot, style: style)
        case .codex:
            // Two equal windows, no credits meter.
            CodexGaugeCluster(snapshot: snapshot, style: style)
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

/// Claude's readout: three windows — weekly (left), the 5-hour "session limit"
/// emphasized in the center, and usage credits (right). Each shows how much is
/// *left* and is colored green/yellow/red. Drawn per the Appearance gauge style.
private struct ClaudeGaugeCluster: View {
    let snapshot: UsageSnapshot
    let style: GaugeStyle

    var body: some View {
        GaugeCluster(items: items, style: style)
    }

    private func window(_ label: String) -> UsageWindow? {
        snapshot.windows.first { $0.label == label }
    }

    private var items: [GaugeContent] {
        let weekly = window("Weekly").map { GaugeContent(window: $0) }
            ?? .placeholder(title: "Weekly")
        let fiveHour = window("5-hour").map { GaugeContent(window: $0, emphasized: true) }
            ?? GaugeContent(title: "5-hour", subtitle: .unavailable, percentRemaining: 0,
                            progress: 0, centerText: "—", emphasized: true, isEnabled: false)
        let credits: GaugeContent = snapshot.credits.map { credits in
            GaugeContent(
                title: "Credits",
                subtitle: .text("of $\(Int(credits.limitDollars.rounded()))"),
                percentRemaining: credits.percentRemaining,
                progress: credits.percentRemaining / 100,
                centerText: "$\(Int(credits.remainingDollars.rounded()))"
            )
        } ?? .placeholder(title: "Credits")
        return [weekly, fiveHour, credits]
    }
}

/// Codex's readout in the same gauge language: two equal windows, no credits.
private struct CodexGaugeCluster: View {
    let snapshot: UsageSnapshot
    let style: GaugeStyle

    private static let diameter: CGFloat = 88

    var body: some View {
        GaugeCluster(items: items, style: style,
                     sideDiameter: Self.diameter, centerDiameter: Self.diameter,
                     sideLineWidth: 6, centerLineWidth: 6, circularSpacing: 18)
    }

    private var items: [GaugeContent] {
        ["5-hour", "Weekly"].map { label in
            snapshot.windows.first { $0.label == label }
                .map { GaugeContent(window: $0) } ?? .placeholder(title: label)
        }
    }
}
