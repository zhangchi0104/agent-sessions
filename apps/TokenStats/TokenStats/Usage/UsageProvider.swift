//
//  UsageProvider.swift
//  TokenStats
//
//  The thin seam the rest of the app talks to. Returns a normalized list of
//  Usage Windows so the UI never depends on any one Coding Agent's specifics
//  (PRD). One conformer per agent, built by that agent's registry entry.
//

import Foundation

/// One fetch's result: the metered Usage Windows.
struct UsageReading {
    let windows: [UsageWindow]
}

protocol UsageProvider {
    /// Fetch the current Usage Windows (primary 5-hour first).
    func fetchUsage() async throws -> UsageReading
}

enum UsageError: Error {
    case notSignedIn
    /// Non-2xx from the usage endpoint; body prefix kept for diagnosis.
    case badResponse(status: Int, body: String)
    /// 200 OK but no recognized Usage Windows — likely the response shape
    /// changed (see ADR-0001). Body prefix kept for diagnosis.
    case noWindows(body: String)
    /// The OAuth login could not complete (e.g. state mismatch, listener error).
    case loginFailed(String)
}

extension UsageError {
    /// A short, user-facing explanation for the popover diagnostics line.
    var displayText: String {
        switch self {
        case .notSignedIn:
            return "Not signed in."
        case .badResponse(let status, let body):
            return "HTTP \(status). \(body.prefix(200))"
        case .noWindows(let body):
            return "Got data but no Usage Windows recognized. \(body.prefix(200))"
        case .loginFailed(let detail):
            return "Login failed. \(detail)"
        }
    }
}
