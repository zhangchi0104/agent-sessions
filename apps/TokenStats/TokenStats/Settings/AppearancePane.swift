//
//  AppearancePane.swift
//  TokenStats
//
//  Settings → Appearance: pick the primary subscription, reorder the Coding
//  Agents, and choose how each Usage Window is drawn.
//

import SwiftUI

/// Appearance: pick the primary subscription, reorder agents, and choose how
/// each Usage Window is drawn. Edits write straight through to the persisted,
/// observable `AppearanceSettings`, so the popover updates live.
struct AppearancePane: View {
    @Bindable var appearance: AppearanceSettings

    /// Reordering only changes anything with at least two *non-primary* agents
    /// to shuffle, since the primary is always hoisted first. With two agents
    /// total there's a single follower, so dragging is a no-op — we disable it
    /// and explain why rather than offer a control that does nothing.
    private var canReorder: Bool { appearance.order.count > 2 }

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
                    OrderRow(appearance: appearance, id: id, draggable: canReorder)
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

            Section {
                Picker("Display mode", selection: $appearance.gaugeStyle) {
                    ForEach(GaugeStyle.allCases) { style in
                        Label(style.title, systemImage: style.icon).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                GaugeStylePreview(style: appearance.gaugeStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } header: {
                Text("Display mode")
            } footer: {
                Text("Choose how each Usage Window is drawn.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

/// One agent row: icon, name, and (for the primary) a badge. When the list is
/// reorderable it carries a trailing drag handle — the affordance hinting the
/// row can be dragged via the enclosing `ForEach`'s native `.onMove`. When only
/// one follower exists the handle is hidden, since dragging does nothing.
private struct OrderRow: View {
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
                            ? "\(id.integration.displayName), primary" : id.integration.displayName)
        .accessibilityHint(draggable ? "Draggable. Drag to reorder." : "")
    }
}

/// A small live sample of the selected gauge style for the Appearance picker.
private struct GaugeStylePreview: View {
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
                     sideDiameter: 60, centerDiameter: 78,
                     sideLineWidth: 5, centerLineWidth: 6, circularSpacing: 16)
            .frame(maxWidth: style == .bar ? 260 : .infinity)
    }
}
