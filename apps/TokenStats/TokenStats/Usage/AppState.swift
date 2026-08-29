//
//  AppState.swift
//  TokenStats
//
//  The UI state machine. The menu-bar label and popover are both derived from
//  this single state, so the app never shows a wrong number — only a fresh one
//  or a disclosed-stale one (see PRD).
//

import Foundation

/// A fetched set of Usage Windows plus when it was fetched.
struct UsageSnapshot: Equatable, Codable {
    let windows: [UsageWindow]
    let fetchedAt: Date
}

enum AppState: Equatable {
    /// No credentials. The Usage tab omits this agent; reconnecting restores
    /// its saved visibility and order.
    case signedOut
    /// Signed in, first data not yet available.
    case loading
    /// Showing a freshly fetched snapshot.
    case fresh(UsageSnapshot)
    /// Showing a last-known snapshot whose refresh failed; disclose its age.
    case staleDisclosed(UsageSnapshot)

}

/// Why a stored OAuth session can no longer be used without signing in again.
/// Keep this structured so UI copy never has to inspect provider response text.
nonisolated enum SessionReauthenticationReason: Equatable, Sendable {
    case unauthorized
    case invalidGrant
    case expired
    case reused
    case invalidated
}

/// Server-side session validity is deliberately separate from `AppState`.
/// A revoked session can still have an honest last-known usage snapshot worth
/// showing, while a network outage must not be mistaken for revocation.
nonisolated enum SessionState: Equatable, Sendable {
    case signedOut
    case checking
    case valid(verifiedAt: Date)
    case reauthenticationRequired(reason: SessionReauthenticationReason)
    case temporarilyUnverifiable(lastVerifiedAt: Date?)

    var isSignedOut: Bool {
        if case .signedOut = self { return true }
        return false
    }

    /// Whether this account should retain a subscription row. A session that
    /// needs reauthentication is still present so the UI can offer recovery.
    var isPresent: Bool { !isSignedOut }

    var lastVerifiedAt: Date? {
        switch self {
        case .valid(let verifiedAt):
            return verifiedAt
        case .temporarilyUnverifiable(let lastVerifiedAt):
            return lastVerifiedAt
        case .signedOut, .checking, .reauthenticationRequired:
            return nil
        }
    }
}

struct CodingAgentSessionStates: Equatable {
    private var states: [CodingAgentID: SessionState]

    init(_ states: [CodingAgentID: SessionState] = [:]) {
        self.states = states
    }

    subscript(_ id: CodingAgentID) -> SessionState {
        get { states[id] ?? .signedOut }
        set { states[id] = newValue }
    }

    func isSignedOut(_ id: CodingAgentID) -> Bool { self[id].isSignedOut }

    func isPresent(_ id: CodingAgentID) -> Bool { self[id].isPresent }
}

enum AppEvent: Equatable {
    case signedOut
    case loadingStarted
    case fetchSucceeded(UsageSnapshot)
    case fetchFailed
}
