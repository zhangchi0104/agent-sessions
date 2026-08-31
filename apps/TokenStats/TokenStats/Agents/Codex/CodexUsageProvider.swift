//
//  CodexUsageProvider.swift
//  TokenStats
//
//  UsageProvider for the Codex Coding Agent. Performs the authenticated GET
//  against the ChatGPT backend usage endpoint and delegates parsing to
//  CodexUsageSnapshotParser. Endpoint and headers are unofficial; see
//  docs/codex-integration.md and ADR-0002. This is a plain read-only GET, so
//  polling it does not consume Codex usage.
//

import Foundation

struct CodexUsageProvider: UsageProvider {
    static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    var session: URLSession = .shared
    /// Supplies a valid ChatGPT bearer token, refreshing silently if needed.
    let accessToken: () async throws -> String
    /// The ChatGPT account id (from the id_token claims), sent as
    /// `ChatGPT-Account-Id`. nil omits the header.
    let accountID: () async throws -> String?

    func fetchUsage() async throws -> UsageReading {
        var request = URLRequest(url: Self.usageEndpoint)
        request.timeoutInterval = 20 // surface a network hang as an error, not an endless spinner
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = try await accountID() {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        // Usage failures can still contain account or backend detail. Preserve
        // only an allow-listed code/type summary for UI diagnostics, never the
        // raw response body or its arbitrary message fields.
        let diagnostic = OAuthErrorDiagnostics.summary(
            data,
            operation: "Codex usage response"
        )
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.badResponse(status: -1, body: diagnostic)
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw UsageError.unauthorized(body: diagnostic)
        case 403:
            throw UsageError.forbidden(body: diagnostic)
        default:
            throw UsageError.badResponse(status: http.statusCode, body: diagnostic)
        }
        let windows = try CodexUsageSnapshotParser.parse(data)
        guard !windows.isEmpty else {
            throw UsageError.noWindows(body: diagnostic)
        }
        return UsageReading(windows: windows)
    }
}
