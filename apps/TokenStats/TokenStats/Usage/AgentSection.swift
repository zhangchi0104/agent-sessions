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

    private var displayName: String { id.integration.displayName }
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

    /// Which windows this agent shows, in what order, and at what size all come
    /// from its registry entry — this view just draws whatever it declares.
    private func windows(_ snapshot: UsageSnapshot) -> some View {
        let layout = id.integration.gaugeLayout
        return GaugeCluster(items: layout.items(for: snapshot),
                            style: model.appearance.gaugeStyle,
                            sideDiameter: layout.sideDiameter,
                            centerDiameter: layout.centerDiameter,
                            sideLineWidth: layout.sideLineWidth,
                            centerLineWidth: layout.centerLineWidth,
                            circularSpacing: layout.circularSpacing)
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
