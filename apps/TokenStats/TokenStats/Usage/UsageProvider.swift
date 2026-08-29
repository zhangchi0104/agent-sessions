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
    /// The usage endpoint rejected the bearer token. The coordinator may force
    /// one token rotation and retry before deciding the session is invalid.
    case unauthorized(body: String)
    /// The bearer token was understood but cannot access this usage resource.
    /// This is not, by itself, proof that the OAuth session was revoked.
    case forbidden(body: String)
    /// Non-2xx from the usage endpoint; only a sanitized response summary is kept.
    case badResponse(status: Int, body: String)
    /// 200 OK but no recognized Usage Windows — likely the response shape
    /// changed (see ADR-0001). Only a sanitized response summary is kept.
    case noWindows(body: String)
    /// The OAuth login could not complete (e.g. state mismatch, listener error).
    case loginFailed(String)
}

extension UsageError {
    /// A short, user-facing explanation for the popover diagnostics line.
    func displayText(using localizer: AppLocalizer) -> String {
        switch self {
        case .notSignedIn:
            return localizer.localized(
                LocalizedStringResource.usageErrorNotSignedInDetail
            )
        case .unauthorized(let body):
            return localizer.localized(
                LocalizedStringResource.usageErrorHttpResponseDetail(
                    401,
                    String(body.prefix(200))
                )
            )
        case .forbidden(let body):
            return localizer.localized(
                LocalizedStringResource.usageErrorHttpResponseDetail(
                    403,
                    String(body.prefix(200))
                )
            )
        case .badResponse(let status, let body):
            return localizer.localized(
                LocalizedStringResource.usageErrorHttpResponseDetail(
                    status,
                    String(body.prefix(200))
                )
            )
        case .noWindows(let body):
            return localizer.localized(
                LocalizedStringResource.usageErrorNoWindowsDetail(
                    String(body.prefix(200))
                )
            )
        case .loginFailed(let detail):
            return localizer.localized(
                LocalizedStringResource.usageErrorLoginFailedDetail(detail)
            )
        }
    }
}
