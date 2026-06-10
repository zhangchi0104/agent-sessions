//
//  AppState.swift
//  TokenStats
//
//  The UI state machine. The menu-bar label and popover are both derived from
//  this single state, so the app never shows a wrong number — only a fresh one
//  or a disclosed-stale one (see PRD).
//

import Foundation

/// A fetched set of Usage Windows plus when it was fetched. `credits` is the
/// optional usage-credit balance (Claude `extra_usage`); nil for agents/plans
/// that don't expose one.
struct UsageSnapshot: Equatable, Codable {
    let windows: [UsageWindow]
    var credits: CreditBalance? = nil
    let fetchedAt: Date
}

/// A pay-as-you-go usage-credit balance (Claude `extra_usage`). Cent-denominated
/// like the source, with dollar/percent conveniences for the UI.
struct CreditBalance: Equatable, Codable {
    /// Credits already spent this period, in cents.
    let usedCents: Double
    /// The period's credit cap, in cents.
    let limitCents: Double
    /// Percent of the cap consumed (0–100), straight from the source.
    let utilization: Double
    /// ISO currency code, e.g. "USD" or "AUD".
    let currency: String

    /// Credits still available, in whole-dollar units.
    var remainingDollars: Double { max(limitCents - usedCents, 0) / 100 }
    /// The cap, in whole-dollar units.
    var limitDollars: Double { limitCents / 100 }
    /// Share of the cap still available, expressed 0–100.
    var percentRemaining: Double { min(max(100 - utilization, 0), 100) }
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
