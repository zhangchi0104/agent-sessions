//
//  DisplayPane.swift
//  TokenStats
//
//  Settings → Display: choose which Coding Agents appear on each surface,
//  arrange them, and select the Usage Window presentation.
//

import SwiftUI

/// Presentation choices shared by the popover and menu bar. Edits write
/// through to the persisted `AppearanceSettings`, so every surface updates
/// immediately while the central non-empty visibility invariant stays intact.
struct DisplayPane: View {
    @Bindable var appearance: AppearanceSettings

    /// With two agents there is only one non-primary follower, so moving it
    /// cannot change the resolved order. Keep the affordance honest until a
    /// third Coding Agent exists.
    private var canReorder: Bool { appearance.order.count > 2 }
    private static let surfaceColumnWidth: CGFloat = 80

    var body: some View {
        Form {
            Section {
                Picker("Primary subscription", selection: $appearance.primaryAgent) {
                    ForEach(CodingAgentID.allCases, id: \.self) { id in
                        Text(id.integration.displayName).tag(id)
                    }
                }
            } header: {
                Text("Primary")
            } footer: {
                Text("Your primary subscription is shown first and badged in the "
                     + "popover and menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(appearance.order, id: \.self) { id in
                    DisplayOrderRow(appearance: appearance, id: id, draggable: canReorder)
                }
                .onMove(perform: canReorder ? { source, destination in
                    appearance.move(fromOffsets: source, toOffset: destination)
                } : nil)
            } header: {
                Text("Order")
            } footer: {
                Text(canReorder
                     ? "Drag to arrange how subscriptions are listed. The primary "
                       + "subscription always leads."
                     : "Nothing to arrange yet — your primary leads and the only "
                       + "other subscription follows. Drag-to-reorder unlocks once "
                       + "you track a third.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            agentVisibilitySection

            Section {
                Picker("Display mode", selection: $appearance.gaugeStyle) {
                    ForEach(GaugeStyle.allCases) { style in
                        Label(style.title, systemImage: style.icon).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                DisplayGaugeStylePreview(style: appearance.gaugeStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } header: {
                Text("Usage Window style")
            } footer: {
                Text("Choose how each Usage Window is drawn.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
    }

    private var agentVisibilitySection: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Agent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    visibilityHeader(.usage)
                    visibilityHeader(.tokens)
                    visibilityHeader(.menuBar)
                }

                ForEach(appearance.displayOrder, id: \.self) { id in
                    GridRow {
                        HStack(spacing: 10) {
                            AgentIconBadge(id: id)
                            Text(id.integration.displayName)
                            if appearance.primaryAgent == id {
                                Text("Primary")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(minWidth: 180, alignment: .leading)

                        visibilityToggle(for: id, on: .usage)
                        visibilityToggle(for: id, on: .tokens)
                        visibilityToggle(for: id, on: .menuBar)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Agent visibility")
        } footer: {
            Text("Each row is an agent. Choose the surfaces where it appears; "
                 + "Tokens excludes unchecked agents from all summaries and totals. "
                 + "At least one agent must remain visible in each column.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func visibilityHeader(_ surface: AgentDisplaySurface) -> some View {
        Text(surface.columnTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: Self.surfaceColumnWidth)
            .multilineTextAlignment(.center)
    }

    private func visibilityToggle(
        for id: CodingAgentID,
        on surface: AgentDisplaySurface
    ) -> some View {
        Toggle("", isOn: visibilityBinding(for: id, on: surface))
            .labelsHidden()
            .controlSize(.small)
            .frame(width: Self.surfaceColumnWidth)
            .disabled(appearance.isVisible(id, on: surface)
                      && !appearance.canHide(id, on: surface))
            .help(appearance.isVisible(id, on: surface)
                  ? "Hide \(id.integration.displayName) from \(surface.helpSurfaceName)"
                  : "Show \(id.integration.displayName) in \(surface.helpSurfaceName)")
            .accessibilityLabel("\(id.integration.displayName), \(surface.columnTitle)")
            .accessibilityValue(appearance.isVisible(id, on: surface) ? "Shown" : "Hidden")
            .accessibilityHint(appearance.isVisible(id, on: surface)
                               && !appearance.canHide(id, on: surface)
                               ? "At least one agent must remain visible."
                               : "")
    }

    private func visibilityBinding(
        for id: CodingAgentID,
        on surface: AgentDisplaySurface
    ) -> Binding<Bool> {
        Binding(
            get: { appearance.isVisible(id, on: surface) },
            set: { isVisible in
                _ = appearance.setVisible(id, on: surface, isVisible: isVisible)
            }
        )
    }
}

private struct DisplayOrderRow: View {
    @Bindable var appearance: AppearanceSettings
    let id: CodingAgentID
    let draggable: Bool

    var body: some View {
        LabeledContent {
            if draggable {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        } label: {
            HStack(spacing: 10) {
                AgentIconBadge(id: id)
                Text(id.integration.displayName)
                if appearance.primaryAgent == id {
                    Text("Primary")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appearance.primaryAgent == id
                            ? "\(id.integration.displayName), primary"
                            : id.integration.displayName)
        .accessibilityHint(draggable ? "Draggable. Drag to reorder." : "")
    }
}

private struct DisplayGaugeStylePreview: View {
    let style: GaugeStyle

    private var sample: [GaugeContent] {
        [
            GaugeContent(title: "5-hour",
                         subtitle: .reset(display: "3h 20m", spoken: "resets in 3h 20m"),
                         percentRemaining: 72, progress: 0.72, centerText: "72%",
                         emphasized: true),
            GaugeContent(title: "Weekly",
                         subtitle: .reset(display: "4d", spoken: "resets in 4d"),
                         percentRemaining: 28, progress: 0.28, centerText: "28%"),
        ]
    }

    var body: some View {
        GaugeCluster(items: sample, style: style,
                     sizing: GaugeSizing(sideDiameter: 60, centerDiameter: 78,
                                         sideLineWidth: 5, centerLineWidth: 6,
                                         circularSpacing: 16))
            .frame(maxWidth: style == .bar ? 260 : .infinity)
    }
}

private extension AgentDisplaySurface {
    var columnTitle: String {
        switch self {
        case .usage: "Usage"
        case .tokens: "Tokens"
        case .menuBar: "Menu bar"
        }
    }

    var helpSurfaceName: String {
        switch self {
        case .usage: "Usage"
        case .tokens: "Tokens and its totals"
        case .menuBar: "the menu bar"
        }
    }
}
