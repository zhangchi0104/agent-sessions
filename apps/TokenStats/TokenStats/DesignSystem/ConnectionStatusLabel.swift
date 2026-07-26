//
//  ConnectionStatusLabel.swift
//  TokenStats
//
//  How one Coding Agent's account state is worded and colored. Settings and
//  onboarding both show it, and used to derive and phrase it separately; this
//  is the single definition, with a style for each surface's treatment.
//

import SwiftUI

/// The connection state shown for one account.
enum ConnectionStatus {
    case connected
    case awaitingCode
    case signedOut

    /// The join of the two axes this status sits on, as a pure function of
    /// both: what the usage state says about the account, and whether a
    /// sign-in for it is mid-flight. Usage state wins — an agent that is
    /// serving data is connected whatever a stale flag says.
    init(state: AppState, awaitingCode: Bool) {
        if state != .signedOut {
            self = .connected
        } else if awaitingCode {
            self = .awaitingCode
        } else {
            self = .signedOut
        }
    }

    /// Read one agent's status out of the model.
    init(model: UsageModel, id: CodingAgentID) {
        self.init(state: model.agentStates[id], awaitingCode: model.isAwaitingCode(id))
    }

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .awaitingCode: return "Awaiting code"
        case .signedOut: return "Not signed in"
        }
    }

    /// The state's own color, or nil for signed-out — which is the absence of a
    /// state rather than a warning, so each style supplies its own neutral.
    fileprivate var accent: Color? {
        switch self {
        case .connected: return .green
        case .awaitingCode: return .orange
        case .signedOut: return nil
        }
    }
}

/// One account's status, drawn either as a dot beside a neutral label (the
/// Settings row, which already carries its own controls) or as the label itself
/// in the status color (the onboarding tile, which has no room for a dot).
struct ConnectionStatusLabel: View {
    let status: ConnectionStatus
    var font: Font = .callout
    var style: Style = .badge

    enum Style {
        /// Colored dot + secondary label.
        case badge
        /// The label itself carries the color.
        case tintedText
    }

    var body: some View {
        switch style {
        case .badge:
            HStack(spacing: 6) {
                Circle()
                    .fill(status.accent ?? .gray)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(font)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.label)
        case .tintedText:
            Text(status.label)
                .font(font)
                .foregroundStyle(status.accent ?? Color.secondary)
        }
    }
}
