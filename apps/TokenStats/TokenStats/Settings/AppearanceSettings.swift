//
//  AppearanceSettings.swift
//  TokenStats
//
//  User-controlled presentation preferences for the popover and menu bar:
//  which Coding Agent is primary, the order agents are shown in, and how each
//  Usage Window is drawn. Persisted to UserDefaults so the choices survive
//  relaunch. The pure `AgentDisplayOrder.resolve` keeps the ordering logic
//  testable away from the @Observable store.
//

import Foundation
import Observation

/// How each Usage Window is drawn in the popover. Three shapes for the same
/// remaining-quota reading — purely a presentation choice (Appearance settings).
enum GaugeStyle: String, CaseIterable, Codable, Identifiable {
    /// The 270° open "speedometer" dial with a gap at the bottom (default).
    case arc270
    /// A closed 360° ring.
    case ring
    /// A horizontal progress bar.
    case bar

    var id: Self { self }

    /// Picker label.
    var title: LocalizedStringResource {
        switch self {
        case .arc270:
            return LocalizedStringResource.settingsAppearanceGaugeStyleDial
        case .ring:
            return LocalizedStringResource.settingsAppearanceGaugeStyleRing
        case .bar:
            return LocalizedStringResource.settingsAppearanceGaugeStyleBar
        }
    }

    /// SF Symbol that previews the shape in the picker.
    var icon: String {
        switch self {
        case .arc270: return "gauge.with.dots.needle.bottom.50percent"
        case .ring: return "circle.dashed"
        case .bar: return "chart.bar.fill"
        }
    }

    /// True for the circular shapes (ring + 270° arc) that share a layout.
    var isCircular: Bool { self != .bar }
}

/// How an enabled Token Kind cell presents its share of the row's selected
/// total. Disabled kinds always keep a dimmed raw value with no percentage.
nonisolated enum TokenValueDisplayMode: String, CaseIterable, Codable, Identifiable {
    case value
    case percentage
    case valueAndPercentage

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .value:
            LocalizedStringResource.settingsAppearanceTokenValueValue
        case .percentage:
            LocalizedStringResource.settingsAppearanceTokenValuePercentage
        case .valueAndPercentage:
            LocalizedStringResource.settingsAppearanceTokenValueValueAndPercentage
        }
    }
}

/// Pure ordering: resolve the order agents are shown in from the primary choice
/// and the saved order. The primary is always first; the rest follow the saved
/// order, and any agent missing from both lists is appended (defensive against
/// a newly added Coding Agent that predates a stored preference).
enum AgentDisplayOrder {
    static func resolve(primary: CodingAgentID, order: [CodingAgentID]) -> [CodingAgentID] {
        var resolved: [CodingAgentID] = [primary]
        for id in order where id != primary { resolved.append(id) }
        for id in CodingAgentID.allCases where !resolved.contains(id) { resolved.append(id) }
        return resolved
    }
}

/// The three independent surfaces whose agent visibility can be customized.
/// Visibility is presentation-only: it never disconnects a subscription or stops
/// the background usage/transcript work for that agent.
nonisolated enum AgentDisplaySurface: String, CaseIterable, Codable, Identifiable {
    case usage
    case tokens
    case menuBar

    var id: Self { self }
}

/// The Appearance preferences, observable so the popover/menu bar re-render on
/// change and persisted so the choices stick. Construction reads any saved
/// values; every mutation writes back.
@MainActor
@Observable
final class AppearanceSettings {
    /// The primary Coding Agent — shown first and badged wherever it is visible.
    var primaryAgent: CodingAgentID { didSet { persist() } }
    /// The saved order of all agents. Per-surface orders filter this list without
    /// removing hidden agents, so re-enabling one restores its prior position.
    var order: [CodingAgentID] { didSet { persist() } }
    /// Agents shown in the Usage tab. At least one agent always remains visible.
    private(set) var usageVisibleAgents: Set<CodingAgentID>
    /// Agents included in the Tokens projection. At least one agent always
    /// remains visible/included.
    private(set) var tokensVisibleAgents: Set<CodingAgentID>
    /// Agents included in the menu-bar summary. At least one agent always
    /// remains visible.
    private(set) var menuBarVisibleAgents: Set<CodingAgentID>
    /// The shape every Usage Window is drawn with.
    var gaugeStyle: GaugeStyle { didSet { persist() } }
    /// Token Kinds included in the table's selected total. Mutated only through
    /// `setTokenKind` so the last enabled kind cannot be turned off.
    private(set) var selectedTokenKinds: Set<TokenKind>
    /// Value / composition presentation for enabled Token Kind cells.
    var tokenValueDisplay: TokenValueDisplayMode { didSet { persist() } }
    /// The Token Odometer range restored on the next tab appearance or launch.
    var selectedTokenRange: TokenRange { didSet { persist() } }

    @ObservationIgnored private let defaults: UserDefaults
    private static let primaryKey = "appearance.primaryAgent"
    private static let orderKey = "appearance.order"
    private static let usageVisibleAgentsKey = "appearance.usageVisibleAgents"
    private static let tokensVisibleAgentsKey = "appearance.tokensVisibleAgents"
    private static let menuBarVisibleAgentsKey = "appearance.menuBarVisibleAgents"
    private static let schemaVersionKey = "appearance.schemaVersion"
    private static let currentSchemaVersion = 1
    private static let styleKey = "appearance.gaugeStyle"
    private static let selectedTokenKindsKey = "appearance.selectedTokenKinds"
    private static let tokenValueDisplayKey = "appearance.tokenValueDisplay"
    private static let selectedTokenRangeKey = "appearance.selectedTokenRange"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedPrimary = (defaults.string(forKey: Self.primaryKey))
            .flatMap(CodingAgentID.init(rawValue:))
        self.primaryAgent = savedPrimary ?? .claudeCode

        let savedOrder = (defaults.array(forKey: Self.orderKey) as? [String] ?? [])
            .compactMap(CodingAgentID.init(rawValue:))
        // Always carry every known agent so reordering and resolution are stable
        // even if a new agent appeared since the order was saved.
        var order = savedOrder
        for id in CodingAgentID.allCases where !order.contains(id) { order.append(id) }
        self.order = order

        self.usageVisibleAgents = Self.loadVisibleAgents(
            defaults: defaults,
            key: Self.usageVisibleAgentsKey,
            allowed: Self.supportedAgents(on: .usage)
        )
        self.tokensVisibleAgents = Self.loadVisibleAgents(
            defaults: defaults,
            key: Self.tokensVisibleAgentsKey,
            allowed: Self.supportedAgents(on: .tokens)
        )
        self.menuBarVisibleAgents = Self.loadVisibleAgents(
            defaults: defaults,
            key: Self.menuBarVisibleAgentsKey,
            allowed: Self.supportedAgents(on: .menuBar)
        )

        let savedStyle = (defaults.string(forKey: Self.styleKey))
            .flatMap(GaugeStyle.init(rawValue:))
        self.gaugeStyle = savedStyle ?? .arc270

        let savedTokenKinds = (defaults.array(forKey: Self.selectedTokenKindsKey) as? [String] ?? [])
            .compactMap(TokenKind.init(rawValue:))
        let tokenKinds = Set(savedTokenKinds)
        self.selectedTokenKinds = tokenKinds.isEmpty ? Set(TokenKind.allCases) : tokenKinds

        let savedTokenValueDisplay = defaults.string(forKey: Self.tokenValueDisplayKey)
            .flatMap(TokenValueDisplayMode.init(rawValue:))
        self.tokenValueDisplay = savedTokenValueDisplay ?? .value

        let savedTokenRange = defaults.string(forKey: Self.selectedTokenRangeKey)
            .flatMap(TokenRange.init(rawValue:))
        self.selectedTokenRange = savedTokenRange ?? .today

        migrateSettingsIfNeeded()
    }

    /// The resolved order for display: primary first, then the saved order.
    var displayOrder: [CodingAgentID] {
        AgentDisplayOrder.resolve(primary: primaryAgent, order: order)
    }

    /// The resolved order for one surface, with hidden agents removed.
    func displayOrder(for surface: AgentDisplaySurface) -> [CodingAgentID] {
        let visible = visibleAgents(on: surface)
        return displayOrder.filter(visible.contains)
    }

    var usageDisplayOrder: [CodingAgentID] {
        displayOrder(for: .usage)
    }

    var tokensDisplayOrder: [CodingAgentID] {
        displayOrder(for: .tokens)
    }

    var menuBarDisplayOrder: [CodingAgentID] {
        displayOrder(for: .menuBar)
    }

    func isVisible(_ id: CodingAgentID, on surface: AgentDisplaySurface) -> Bool {
        visibleAgents(on: surface).contains(id)
    }

    /// Whether turning this agent off is allowed without leaving a surface
    /// empty. The UI uses this to disable the final visible toggle and the
    /// mutation API repeats the guard for non-UI callers.
    func canHide(_ id: CodingAgentID, on surface: AgentDisplaySurface) -> Bool {
        isVisible(id, on: surface) && visibleAgents(on: surface).count > 1
    }

    /// Shows or hides one agent on one surface. The preference is deliberately
    /// independent of sign-in state: hiding preserves credentials and all
    /// background refresh/transcript work, while re-enabling reveals the latest
    /// already-available state immediately.
    ///
    /// - Returns: `false` only when hiding `id` would leave the surface empty.
    @discardableResult
    func setVisible(_ id: CodingAgentID,
                    on surface: AgentDisplaySurface,
                    isVisible: Bool) -> Bool {
        guard Self.supportedAgents(on: surface).contains(id) else { return false }
        var next = visibleAgents(on: surface)
        if isVisible {
            next.insert(id)
        } else {
            next.remove(id)
        }
        guard !next.isEmpty else { return false }
        guard next != visibleAgents(on: surface) else { return true }

        switch surface {
        case .usage:
            usageVisibleAgents = next
        case .tokens:
            tokensVisibleAgents = next
        case .menuBar:
            menuBarVisibleAgents = next
        }
        persist()
        return true
    }

    /// Reorder agents from a native SwiftUI `.onMove` drag. Mirrors the
    /// `IndexSet`/offset contract `ForEach` hands back: the items at `source`
    /// are lifted out and reinserted ahead of whatever currently sits at
    /// `destination`. Implemented here (rather than leaning on SwiftUI's
    /// collection helper) so the model stays UI-free and unit-testable.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { order[$0] }
        guard !moving.isEmpty else { return }
        var reordered = order
        for index in source.sorted(by: >) { reordered.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: insertAt)
        guard reordered != order else { return }
        order = reordered
    }

    /// Enable or disable one Token Kind. At least one kind must remain selected
    /// so every subtotal and percentage keeps a meaningful denominator.
    ///
    /// - Returns: `false` only when disabling `kind` would clear the selection.
    @discardableResult
    func setTokenKind(_ kind: TokenKind, isSelected: Bool) -> Bool {
        var next = selectedTokenKinds
        if isSelected {
            next.insert(kind)
        } else {
            next.remove(kind)
        }
        guard !next.isEmpty else { return false }
        guard next != selectedTokenKinds else { return true }
        selectedTokenKinds = next
        persist()
        return true
    }

    private func visibleAgents(on surface: AgentDisplaySurface) -> Set<CodingAgentID> {
        switch surface {
        case .usage: usageVisibleAgents
        case .tokens: tokensVisibleAgents
        case .menuBar: menuBarVisibleAgents
        }
    }

    private static func loadVisibleAgents(defaults: UserDefaults,
                                          key: String,
                                          allowed: Set<CodingAgentID>) -> Set<CodingAgentID> {
        // A missing key enables every agent supported by this surface.
        guard defaults.object(forKey: key) != nil else {
            return allowed
        }

        let saved = (defaults.array(forKey: key) as? [String] ?? [])
            .compactMap(CodingAgentID.init(rawValue:))
        let supported = Set(saved).intersection(allowed)
        guard !supported.isEmpty else {
            // A present-but-empty or otherwise corrupt value must not violate
            // the non-empty surface invariant. Claude is the existing default
            // primary and the stable repair target.
            let fallback: Set<CodingAgentID> = [.claudeCode]
            defaults.set([CodingAgentID.claudeCode.rawValue], forKey: key)
            return fallback
        }
        return supported
    }

    private static func supportedAgents(on surface: AgentDisplaySurface) -> Set<CodingAgentID> {
        switch surface {
        case .usage, .menuBar:
            return Set(CodingAgentID.allCases)
        case .tokens:
            return Set(CodingAgentRegistry.all.compactMap { integration in
                integration.transcriptRoot == nil ? nil : integration.id
            })
        }
    }

    private func migrateSettingsIfNeeded() {
        let storedVersion = defaults.integer(forKey: Self.schemaVersionKey)
        guard storedVersion < Self.currentSchemaVersion else { return }

        var visibilityChanged = false
        if storedVersion < 1 {
            // Version 1 introduced Cursor. Only explicit pre-existing lists
            // need repair; missing lists already resolve to all agents that
            // support the surface.
            if defaults.object(forKey: Self.usageVisibleAgentsKey) != nil,
               usageVisibleAgents.insert(.cursor).inserted {
                visibilityChanged = true
            }
            if defaults.object(forKey: Self.menuBarVisibleAgentsKey) != nil,
               menuBarVisibleAgents.insert(.cursor).inserted {
                visibilityChanged = true
            }
        }

        defaults.set(Self.currentSchemaVersion, forKey: Self.schemaVersionKey)
        if visibilityChanged { persist() }
    }

    private func persist() {
        defaults.set(primaryAgent.rawValue, forKey: Self.primaryKey)
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        defaults.set(
            CodingAgentID.allCases.filter(usageVisibleAgents.contains).map(\.rawValue),
            forKey: Self.usageVisibleAgentsKey
        )
        defaults.set(
            CodingAgentID.allCases.filter(tokensVisibleAgents.contains).map(\.rawValue),
            forKey: Self.tokensVisibleAgentsKey
        )
        defaults.set(
            CodingAgentID.allCases.filter(menuBarVisibleAgents.contains).map(\.rawValue),
            forKey: Self.menuBarVisibleAgentsKey
        )
        defaults.set(gaugeStyle.rawValue, forKey: Self.styleKey)
        defaults.set(
            TokenKind.allCases.filter(selectedTokenKinds.contains).map(\.rawValue),
            forKey: Self.selectedTokenKindsKey
        )
        defaults.set(tokenValueDisplay.rawValue, forKey: Self.tokenValueDisplayKey)
        defaults.set(selectedTokenRange.rawValue, forKey: Self.selectedTokenRangeKey)
    }
}
