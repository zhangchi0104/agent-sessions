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
    case checking
    case reauthenticationRequired
    case temporarilyUnverifiable
    case awaitingCode
    case signingIn
    case signedOut

    /// Joins the server-verified session state with the two sign-in phases:
    /// browser polling and the paste-code handoff. A verified session wins over
    /// stale sign-in flags; otherwise an active reconnect flow wins over the
    /// previous failure so the row immediately reflects what the user started.
    init(sessionState: SessionState, awaitingCode: Bool, signingIn: Bool = false) {
        if case .valid = sessionState {
            self = .connected
        } else if awaitingCode {
            self = .awaitingCode
        } else if signingIn {
            self = .signingIn
        } else {
            switch sessionState {
            case .signedOut:
                self = .signedOut
            case .checking:
                self = .checking
            case .valid:
                self = .connected
            case .reauthenticationRequired:
                self = .reauthenticationRequired
            case .temporarilyUnverifiable:
                self = .temporarilyUnverifiable
            }
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .connected:
            return LocalizedStringResource.accountStatusConnected
        case .checking:
            return LocalizedStringResource.accountStatusChecking
        case .reauthenticationRequired:
            return LocalizedStringResource.accountStatusReauthenticationRequired
        case .temporarilyUnverifiable:
            return LocalizedStringResource.accountStatusTemporarilyUnverifiable
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
        case .reauthenticationRequired: return .red
        case .checking, .temporarilyUnverifiable, .awaitingCode, .signingIn: return .orange
        case .signedOut: return nil
        }
    }
}

/// Pure session-state presentation rules shared by Settings, onboarding, and
/// the popover. Keeping these queries here prevents each surface from silently
/// redefining "connected" as "a token exists" again.
enum SessionPresentation {
    static func keepsSubscriptionVisible(_ state: SessionState) -> Bool {
        if case .signedOut = state { return false }
        return true
    }

    static func isVerified(_ state: SessionState) -> Bool {
        if case .valid = state { return true }
        return false
    }

    static func requiresSignIn(_ state: SessionState) -> Bool {
        switch state {
        case .signedOut, .reauthenticationRequired:
            return true
        case .checking, .valid, .temporarilyUnverifiable:
            return false
        }
    }

    /// A paste-code flow moves the stored session to `checking` while the
    /// browser is open. Keep its controls visible until the user submits the
    /// code even though `checking` does not normally offer a new sign-in.
    static func showsSignInControls(
        _ state: SessionState,
        awaitingCode: Bool
    ) -> Bool {
        awaitingCode || requiresSignIn(state)
    }

    static func isChecking(_ state: SessionState) -> Bool {
        if case .checking = state { return true }
        return false
    }

    static func isTemporarilyUnverifiable(_ state: SessionState) -> Bool {
        if case .temporarilyUnverifiable = state { return true }
        return false
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
