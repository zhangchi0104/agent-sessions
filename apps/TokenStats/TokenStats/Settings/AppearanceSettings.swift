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
    var title: String {
        switch self {
        case .arc270: return "Dial"
        case .ring: return "Ring"
        case .bar: return "Bar"
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

/// Which objective summary leads the Tokens tab. The raw Token Odometer and
/// Token Kind table remain unchanged whichever presentation is selected.
nonisolated enum TokenSummaryMetric: String, CaseIterable, Codable, Identifiable {
    case apiEquivalent
    case billingTokens

    var id: Self { self }

    var title: String {
        switch self {
        case .apiEquivalent: "API equivalent"
        case .billingTokens: "Billing tokens"
        }
    }
}

/// How an enabled Token Kind cell presents its share of the row's selected
/// total. Disabled kinds always keep a dimmed raw value with no percentage.
nonisolated enum TokenValueDisplayMode: String, CaseIterable, Codable, Identifiable {
    case value
    case percentage
    case valueAndPercentage

    var id: Self { self }

    var title: String {
        switch self {
        case .value: "Value"
        case .percentage: "Percentage"
        case .valueAndPercentage: "Value (percentage)"
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

/// The Appearance preferences, observable so the popover/menu bar re-render on
/// change and persisted so the choices stick. Construction reads any saved
/// values; every mutation writes back.
@MainActor
@Observable
final class AppearanceSettings {
    /// The primary Coding Agent — shown first and badged in the popover.
    var primaryAgent: CodingAgentID { didSet { persist() } }
    /// The saved order of the non-primary agents (see `displayOrder`).
    var order: [CodingAgentID] { didSet { persist() } }
    /// The shape every Usage Window is drawn with.
    var gaugeStyle: GaugeStyle { didSet { persist() } }
    /// The objective summary shown above the Token Odometer.
    var tokenSummaryMetric: TokenSummaryMetric { didSet { persist() } }
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
    private static let styleKey = "appearance.gaugeStyle"
    private static let tokenSummaryMetricKey = "appearance.tokenSummaryMetric"
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

        let savedStyle = (defaults.string(forKey: Self.styleKey))
            .flatMap(GaugeStyle.init(rawValue:))
        self.gaugeStyle = savedStyle ?? .arc270

        let savedSummaryMetric = defaults.string(forKey: Self.tokenSummaryMetricKey)
            .flatMap(TokenSummaryMetric.init(rawValue:))
        self.tokenSummaryMetric = savedSummaryMetric ?? .billingTokens

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
    }

    /// The resolved order for display: primary first, then the saved order.
    var displayOrder: [CodingAgentID] {
        AgentDisplayOrder.resolve(primary: primaryAgent, order: order)
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

    private func persist() {
        defaults.set(primaryAgent.rawValue, forKey: Self.primaryKey)
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        defaults.set(gaugeStyle.rawValue, forKey: Self.styleKey)
        defaults.set(tokenSummaryMetric.rawValue, forKey: Self.tokenSummaryMetricKey)
        defaults.set(
            TokenKind.allCases.filter(selectedTokenKinds.contains).map(\.rawValue),
            forKey: Self.selectedTokenKindsKey
        )
        defaults.set(tokenValueDisplay.rawValue, forKey: Self.tokenValueDisplayKey)
        defaults.set(selectedTokenRange.rawValue, forKey: Self.selectedTokenRangeKey)
    }
}
