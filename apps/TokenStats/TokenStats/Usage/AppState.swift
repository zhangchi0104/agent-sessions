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
    /// No credentials — show a neutral placeholder and a sign-in action.
    case signedOut
    /// Signed in, first data not yet available.
    case loading
    /// Showing a freshly fetched snapshot.
    case fresh(UsageSnapshot)
    /// Showing a last-known snapshot whose refresh failed; disclose its age.
    case staleDisclosed(UsageSnapshot)
}

enum AppEvent: Equatable {
    case signedOut
    case loadingStarted
    case fetchSucceeded(UsageSnapshot)
    case fetchFailed
}
