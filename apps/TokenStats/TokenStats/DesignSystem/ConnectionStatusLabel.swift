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

    /// Read one agent's state out of the model. Awaiting-code only applies to
    /// the paste-a-code sign-in flow, which today is Claude Code's.
    init(model: UsageModel, id: CodingAgentID) {
        if model.agentStates[id] != .signedOut {
            self = .connected
        } else if id == .claudeCode && model.isAwaitingCode {
            self = .awaitingCode
        } else {
            self = .signedOut
        }
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
