//
//  ClaudeCodeUsageProvider.swift
//  TokenStats
//
//  Sole UsageProvider for the MVP. Performs the authenticated GET against the
//  OAuth usage endpoint and delegates parsing to UsageSnapshotParser.
//  Endpoint is unofficial; see docs/claude-code-integration.md and ADR-0001.
//

import Foundation

struct ClaudeCodeUsageProvider: UsageProvider {
    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    var session: URLSession = .shared
    /// Supplies a valid bearer token, refreshing silently if needed.
    let accessToken: () async throws -> String

    func fetchUsage() async throws -> UsageReading {
        var request = URLRequest(url: Self.usageEndpoint)
        request.timeoutInterval = 20 // surface a network hang as an error, not an endless spinner
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let body = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.badResponse(status: -1, body: body)
        }
        guard http.statusCode == 200 else {
            throw UsageError.badResponse(status: http.statusCode, body: body)
        }
        let windows = try UsageSnapshotParser.parse(data)
        guard !windows.isEmpty else {
            throw UsageError.noWindows(body: body)
        }
        return UsageReading(windows: windows, credits: UsageSnapshotParser.parseCredits(data))
    }
}
