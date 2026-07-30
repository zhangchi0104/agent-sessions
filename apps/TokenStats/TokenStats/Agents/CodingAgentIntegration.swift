//
//  CodingAgentIntegration.swift
//  TokenStats
//
//  Everything that varies from one Coding Agent to the next, declared in one
//  place per agent. Before this existed the same two agents were spelled out
//  again in the menu-bar labels, the provider table, the sign-out and
//  signed-in checks, the icon badge, the gauge layout, the sign-in controls,
//  and the transcript scan roots. Adding a third agent meant finding all of
//  them; now it means one conformance and one line in the registry.
//

import SwiftUI

/// An agent's mark in the asset catalog and the tile color behind it.
struct AgentBrand {
    /// A template SVG in the asset catalog, tinted white over `tint`.
    let assetName: String
    let tint: Color
}

/// What a browser sign-in still asks of the user once the browser is open.
///
/// Both cases name the user-visible step, never the transport underneath it —
/// how an approval finds its way back to the app is that agent's own business,
/// and a UI that knows about it is a UI that will reach for agent identity.
enum SignInStyle: Equatable {
    /// The browser shows a code the user has to paste into TokenStats.
    case pasteCode
    /// Nothing further to do; the app completes the sign-in on its own.
    case selfCompleting
}

/// How one Coding Agent's Usage Windows are drawn: which windows, in what
/// order, which one carries the emphasis, and the circular sizing that suits
/// that many dials.
struct GaugeLayout {
    /// One fixed slot in the row, in display order. An empty list means the
    /// agent's returned windows are the layout: only actual readings are drawn.
    struct Slot {
        let label: String
        var emphasized: Bool = false
    }

    let slots: [Slot]
    /// Geometry for the circular styles. The numbers themselves live on
    /// `GaugeSizing` in the design system; an agent only overrides what its own
    /// slot count needs.
    var sizing = GaugeSizing()

    /// The readings to draw for one snapshot: each slot filled from the window
    /// that matches it, or a neutral placeholder when the plan doesn't expose
    /// that window. Agents with no fixed slots render the snapshot dynamically
    /// instead, so a missing window does not create an invented placeholder.
    func items(for snapshot: UsageSnapshot) -> [GaugeContent] {
        guard !slots.isEmpty else {
            return snapshot.windows.map { GaugeContent(window: $0) }
        }
        return slots.map { slot in
            snapshot.windows.first { $0.label == slot.label }
                .map { GaugeContent(window: $0, emphasized: slot.emphasized) }
                ?? .placeholder(title: slot.label, emphasized: slot.emphasized)
        }
    }
}

/// One Coding Agent, and every fact about it the rest of the app needs.
protocol CodingAgentIntegration {
    var id: CodingAgentID { get }
    /// The full name shown in the popover and Settings (glossary).
    var displayName: String { get }
    /// The compact menu-bar label used when more than one agent is readable.
    var shortLabel: String { get }
    var brand: AgentBrand { get }
    var auth: any AgentAuthSession { get }
    var signInStyle: SignInStyle { get }
    var gaugeLayout: GaugeLayout { get }
    /// The directory the Token Odometer scans for this agent's transcripts.
    var transcriptRoot: String { get }

    func makeProvider() -> UsageProvider
}

extension CodingAgentID {
    /// This agent's registered integration — the single declaration of every
    /// per-agent fact.
    var integration: any CodingAgentIntegration { CodingAgentRegistry.agent(self) }
}
