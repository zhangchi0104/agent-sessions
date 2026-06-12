//
//  AgentSection.swift
//  TokenStats
//
//  One Coding Agent's section of the Usage tab: name (with the Primary badge
//  per the Appearance setting), the agent's Usage Window gauges, the
//  right-aligned last-updated / staleness line with inline-expandable error
//  diagnostics, and the signed-out state's pointer to Settings.
//

import SwiftUI

struct AgentSection: View {
    let model: UsageModel
    let id: CodingAgentID
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDiagnosticsExpanded = false

    private var displayName: String { id.displayName }
    private var isPrimary: Bool { model.appearance.primaryAgent == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayName).font(.body.weight(.semibold))
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
                Text("Loading usage…").font(.callout).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Not signed in to \(displayName).")
                .font(.callout)
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

    /// Diagnostics expand inline below the status line rather than in a
    /// .popover — a popover sprouting from inside the menu-bar popover is
    /// disorienting and steals focus from the surface the user just opened.
    @ViewBuilder private func statusLine(text: String,
                                         isStale: Bool,
                                         diagnostics: String? = nil) -> some View {
        // The updated-time line sits right-aligned, tucked under the gauges'
        // trailing edge; the expanded diagnostics below stay full-width.
        if let diagnostics, diagnostics.isEmpty == false {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        isDiagnosticsExpanded.toggle()
                    }
                } label: {
                    StatusLineContent(text: text, isStale: isStale,
                                      showsDetailsIndicator: true,
                                      isExpanded: isDiagnosticsExpanded)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(isDiagnosticsExpanded ? "Hide error details" : "Show error details")
                .accessibilityLabel("\(text). \(isDiagnosticsExpanded ? "Hide" : "Show") error details")

                if isDiagnosticsExpanded {
                    ScrollView {
                        Text(diagnostics)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Tall enough that long network error traces read without
                    // immediate scrolling, but capped so the popover stays
                    // within its height budget on small screens. Indicators
                    // stay visible so a clipped trace reads as scrollable.
                    .frame(maxHeight: 160)
                    .scrollIndicators(.visible)
                }
            }
        } else {
            StatusLineContent(text: text, isStale: isStale, showsDetailsIndicator: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// A small "Primary" tag next to the primary agent's name (Appearance setting).
private struct PrimaryBadge: View {
    var body: some View {
        Text("Primary")
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .accessibilityLabel("Primary subscription")
    }
}

private struct StatusLineContent: View {
    let text: String
    let isStale: Bool
    let showsDetailsIndicator: Bool
    /// Whether the inline diagnostics below this line are showing; turns the
    /// disclosure chevron downward.
    var isExpanded: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)

            if showsDetailsIndicator {
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    // Long status text must not compress or displace the chevron.
                    .fixedSize()
            }
        }
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

    // Sized as a deliberate two-up pair, not Claude's three-slot row with the
    // center missing: equal dials larger than Claude's side dials, with wide
    // spacing, centered in the popover's 300pt content width (96+32+96 = 224).
    private static let diameter: CGFloat = 96
    private static let spacing: CGFloat = 32

    var body: some View {
        GaugeCluster(items: items, style: style,
                     sideDiameter: Self.diameter, centerDiameter: Self.diameter,
                     sideLineWidth: 6, centerLineWidth: 6, circularSpacing: Self.spacing)
    }

    private var items: [GaugeContent] {
        ["5-hour", "Weekly"].map { label in
            snapshot.windows.first { $0.label == label }
                .map { GaugeContent(window: $0) } ?? .placeholder(title: label)
        }
    }
}
