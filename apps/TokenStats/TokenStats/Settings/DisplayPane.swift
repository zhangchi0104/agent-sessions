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
                Picker(selection: $appearance.primaryAgent) {
                    ForEach(CodingAgentID.allCases, id: \.self) { id in
                        Text(id.integration.displayName).tag(id)
                    }
                } label: {
                    Text(AppearanceCopy.primarySubscriptionPicker)
                }
            } header: {
                Text(AppearanceCopy.primarySectionTitle)
            } footer: {
                Text(AppearanceCopy.primaryFooter)
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
                Text(AppearanceCopy.orderSectionTitle)
            } footer: {
                Text(canReorder
                     ? AppearanceCopy.orderReorderableFooter
                     : AppearanceCopy.orderFixedFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            agentVisibilitySection

            Section {
                Picker(selection: $appearance.gaugeStyle) {
                    ForEach(GaugeStyle.allCases) { style in
                        Label {
                            Text(style.title)
                        } icon: {
                            Image(systemName: style.icon)
                        }
                        .tag(style)
                    }
                } label: {
                    Text(AppearanceCopy.gaugeStylePicker)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                DisplayGaugeStylePreview(style: appearance.gaugeStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } header: {
                Text(AppearanceCopy.gaugeStyleSectionTitle)
            } footer: {
                Text(AppearanceCopy.gaugeStyleFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(AppearanceCopy.title))
    }

    private var agentVisibilitySection: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text(AppearanceCopy.agentColumnTitle)
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
                                Text(AppearanceCopy.primaryBadge)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(minWidth: 180, alignment: .leading)

                        visibilityCell(for: id, on: .usage)
                        visibilityCell(for: id, on: .tokens)
                        visibilityCell(for: id, on: .menuBar)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(AppearanceCopy.visibilitySectionTitle)
        } footer: {
            Text(AppearanceCopy.visibilityFooter)
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

    @ViewBuilder
    private func visibilityCell(for id: CodingAgentID,
                                on surface: AgentDisplaySurface) -> some View {
        if surface == .tokens, id.integration.transcriptRoot == nil {
            // i18n-ignore: invariant em dash marks an unsupported surface
            Text(verbatim: "—")
                .foregroundStyle(.tertiary)
                .frame(width: Self.surfaceColumnWidth)
                .accessibilityHidden(true)
        } else {
            visibilityToggle(for: id, on: surface)
        }
    }

    private func visibilityToggle(for id: CodingAgentID,
                                  on surface: AgentDisplaySurface) -> some View {
        let isVisible = appearance.isVisible(id, on: surface)
        let mustRemainVisible = isVisible && !appearance.canHide(id, on: surface)

        return Toggle(isOn: visibilityBinding(for: id, on: surface)) {
            EmptyView()
        }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: Self.surfaceColumnWidth)
            .disabled(mustRemainVisible)
            .help(Text(surface.visibilityHelp(
                agentName: id.integration.displayName,
                isVisible: isVisible
            )))
            .accessibilityLabel(Text(surface.visibilityAccessibilityLabel(
                agentName: id.integration.displayName
            )))
            .accessibilityValue(Text(
                isVisible ? AppearanceCopy.shownAccessibilityValue : AppearanceCopy.hiddenAccessibilityValue
            ))
            .accessibilityHint(
                mustRemainVisible
                    ? Text(AppearanceCopy.minimumVisibleAccessibilityHint)
                    : Text(verbatim: "")
            )
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
                    Text(AppearanceCopy.primaryBadge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            appearance.primaryAgent == id
                ? Text(AppearanceCopy.primaryOrderAccessibilityLabel(id.integration.displayName))
                : Text(verbatim: id.integration.displayName)
        )
        .accessibilityHint(
            draggable
                ? Text(AppearanceCopy.reorderAccessibilityHint)
                : Text(verbatim: "")
        )
    }
}

private struct DisplayGaugeStylePreview: View {
    let style: GaugeStyle
    @Environment(\.locale) private var locale

    private var sample: [GaugeContent] {
        let shortTermDuration = Duration.seconds((3 * 60 * 60) + (20 * 60))
        let weeklyDuration = Duration.seconds(4 * 24 * 60 * 60)
        let shortTermSpokenDuration = shortTermDuration.formatted(
            .units(allowed: [.hours, .minutes], width: .wide).locale(locale)
        )
        let weeklySpokenDuration = weeklyDuration.formatted(
            .units(allowed: [.days], width: .wide).locale(locale)
        )

        return [
            GaugeContent(identity: .shortTerm,
                         title: localized(AppearanceCopy.previewShortTermTitle),
                         subtitle: .reset(
                             display: shortTermDuration.formatted(
                                 .units(allowed: [.hours, .minutes], width: .narrow).locale(locale)
                             ),
                             spoken: localized(AppearanceCopy.previewResetSpoken(
                                 duration: shortTermSpokenDuration
                             ))
                         ),
                         percentRemaining: 72, progress: 0.72,
                         centerText: 0.72.formatted(
                             .percent.precision(.fractionLength(0)).locale(locale)
                         ),
                         emphasized: true,
                         localizer: AppLocalizer(locale: locale)),
            GaugeContent(identity: .weekly,
                         title: localized(AppearanceCopy.previewWeeklyTitle),
                         subtitle: .reset(
                             display: weeklyDuration.formatted(
                                 .units(allowed: [.days], width: .narrow).locale(locale)
                             ),
                             spoken: localized(AppearanceCopy.previewResetSpoken(
                                 duration: weeklySpokenDuration
                             ))
                         ),
                         percentRemaining: 28, progress: 0.28,
                         centerText: 0.28.formatted(
                             .percent.precision(.fractionLength(0)).locale(locale)
                         ),
                         localizer: AppLocalizer(locale: locale)),
        ]
    }

    var body: some View {
        GaugeCluster(items: sample, style: style,
                     sizing: GaugeSizing(sideDiameter: 60, centerDiameter: 78,
                                         sideLineWidth: 5, centerLineWidth: 6,
                                         circularSpacing: 16))
            .frame(maxWidth: style == .bar ? 260 : .infinity)
    }

    private func localized(_ resource: LocalizedStringResource) -> String {
        AppLocalizer(locale: locale).localized(resource)
    }
}

private extension AgentDisplaySurface {
    var columnTitle: LocalizedStringResource {
        switch self {
        case .usage: AppearanceCopy.usageColumnTitle
        case .tokens: AppearanceCopy.tokensColumnTitle
        case .menuBar: AppearanceCopy.menuBarColumnTitle
        }
    }

    func visibilityHelp(agentName: String, isVisible: Bool) -> LocalizedStringResource {
        switch (self, isVisible) {
        case (.usage, true): AppearanceCopy.hideFromUsageHelp(agentName)
        case (.usage, false): AppearanceCopy.showInUsageHelp(agentName)
        case (.tokens, true): AppearanceCopy.hideFromTokensHelp(agentName)
        case (.tokens, false): AppearanceCopy.showInTokensHelp(agentName)
        case (.menuBar, true): AppearanceCopy.hideFromMenuBarHelp(agentName)
        case (.menuBar, false): AppearanceCopy.showInMenuBarHelp(agentName)
        }
    }
    func visibilityAccessibilityLabel(agentName: String) -> LocalizedStringResource {
        switch self {
        case .usage: AppearanceCopy.usageVisibilityAccessibilityLabel(agentName)
        case .tokens: AppearanceCopy.tokensVisibilityAccessibilityLabel(agentName)
        case .menuBar: AppearanceCopy.menuBarVisibilityAccessibilityLabel(agentName)
        }
    }
}

private enum AppearanceCopy {
    static let title = LocalizedStringResource.settingsDisplayTitle

    static let primarySubscriptionPicker = LocalizedStringResource.settingsAppearancePrimarySubscriptionPicker

    static let primarySectionTitle = LocalizedStringResource.settingsAppearancePrimarySection

    static let primaryFooter = LocalizedStringResource.settingsAppearancePrimaryFooter

    static let orderSectionTitle = LocalizedStringResource.settingsAppearanceOrderSection

    static let orderReorderableFooter = LocalizedStringResource.settingsAppearanceOrderReorderableFooter

    static let orderFixedFooter = LocalizedStringResource.settingsAppearanceOrderFixedFooter

    static let gaugeStylePicker = LocalizedStringResource.settingsAppearanceUsageWindowStylePicker

    static let gaugeStyleSectionTitle = LocalizedStringResource.settingsAppearanceUsageWindowStyleSection

    static let gaugeStyleFooter = LocalizedStringResource.settingsAppearanceUsageWindowStyleFooter

    static let agentColumnTitle = LocalizedStringResource.settingsAppearanceVisibilityAgentColumn

    static let primaryBadge = LocalizedStringResource.settingsAppearancePrimaryBadge

    static let visibilitySectionTitle = LocalizedStringResource.settingsAppearanceVisibilitySection

    static let visibilityFooter = LocalizedStringResource.settingsAppearanceVisibilityFooter

    static let usageColumnTitle = LocalizedStringResource.settingsAppearanceVisibilityUsageColumn

    static let tokensColumnTitle = LocalizedStringResource.settingsAppearanceVisibilityTokensColumn

    static let menuBarColumnTitle = LocalizedStringResource.settingsAppearanceVisibilityMenuBarColumn

    static let shownAccessibilityValue = LocalizedStringResource.settingsAppearanceVisibilityShownAccessibilityValue

    static let hiddenAccessibilityValue = LocalizedStringResource.settingsAppearanceVisibilityHiddenAccessibilityValue

    static let minimumVisibleAccessibilityHint =
        LocalizedStringResource.settingsAppearanceVisibilityMinimumAccessibilityHint

    static func primaryOrderAccessibilityLabel(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceOrderPrimaryAccessibilityLabel(agentName)
    }

    static let reorderAccessibilityHint = LocalizedStringResource.settingsAppearanceOrderReorderAccessibilityHint

    static func hideFromUsageHelp(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityUsageHideHelp(agentName)
    }

    static func showInUsageHelp(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityUsageShowHelp(agentName)
    }

    static func hideFromTokensHelp(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityTokensHideHelp(agentName)
    }

    static func showInTokensHelp(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityTokensShowHelp(agentName)
    }

    static func hideFromMenuBarHelp(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityMenuBarHideHelp(agentName)
    }

    static func showInMenuBarHelp(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityMenuBarShowHelp(agentName)
    }

    static func usageVisibilityAccessibilityLabel(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityUsageAccessibilityLabel(agentName)
    }

    static func tokensVisibilityAccessibilityLabel(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityTokensAccessibilityLabel(agentName)
    }

    static func menuBarVisibilityAccessibilityLabel(_ agentName: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceVisibilityMenuBarAccessibilityLabel(agentName)
    }

    static let previewShortTermTitle = LocalizedStringResource.usageWindowShortTerm

    static let previewWeeklyTitle = LocalizedStringResource.usageWindowWeekly

    static func previewResetSpoken(duration: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsAppearanceGaugePreviewResetSpoken(duration)
    }
}
