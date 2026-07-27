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

    @ObservationIgnored private let defaults: UserDefaults
    private static let primaryKey = "appearance.primaryAgent"
    private static let orderKey = "appearance.order"
    private static let styleKey = "appearance.gaugeStyle"

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

    private func persist() {
        defaults.set(primaryAgent.rawValue, forKey: Self.primaryKey)
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        defaults.set(gaugeStyle.rawValue, forKey: Self.styleKey)
    }
}
