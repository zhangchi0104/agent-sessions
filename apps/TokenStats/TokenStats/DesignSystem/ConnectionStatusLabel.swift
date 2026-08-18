//
//  ConnectionStatusLabel.swift
//  TokenStats
//
//  How one Coding Agent subscription's connection state is worded and colored. Settings and
//  onboarding both show it, and used to derive and phrase it separately; this
//  is the single definition, with a style for each surface's treatment.
//

import SwiftUI

/// The connection state shown for one subscription.
enum ConnectionStatus {
    case connected
    case awaitingCode
    case signingIn
    case signedOut

    /// Joins usage state with the two sign-in phases: browser polling and the
    /// paste-code handoff. Usage state wins — an agent that is serving data is
    /// connected whatever a stale sign-in flag says.
    init(state: AppState, awaitingCode: Bool, signingIn: Bool = false) {
        if state != .signedOut {
            self = .connected
        } else if awaitingCode {
            self = .awaitingCode
        } else if signingIn {
            self = .signingIn
        } else {
            self = .signedOut
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .connected:
            return LocalizedStringResource.accountStatusConnected
        case .awaitingCode:
            return LocalizedStringResource.accountStatusAwaitingCode
        case .signingIn:
            return LocalizedStringResource.accountStatusSigningIn
        case .signedOut:
            return LocalizedStringResource.accountStatusSignedOut
        }
    }

    /// The state's own color, or nil for signed-out — which is the absence of a
    /// state rather than a warning, so each style supplies its own neutral.
    fileprivate var accent: Color? {
        switch self {
        case .connected: return .green
        case .awaitingCode, .signingIn: return .orange
        case .signedOut: return nil
        }
    }
}

/// One subscription's status, drawn either as a dot beside a neutral label (the
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
