//
//  CursorUsageProvider.swift
//  TokenStats
//
//  Read-only Cursor DashboardService usage RPC. The endpoint is unofficial;
//  see docs/cursor-integration.md and ADR-0010.
//

import Foundation

struct CursorUsageProvider: UsageProvider {
    static let usageEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )!

    var session: URLSession = .shared
    let accessToken: () async throws -> String

    func fetchUsage() async throws -> UsageReading {
        var request = URLRequest(url: Self.usageEndpoint)
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-request-id")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        let body = String(data: data.prefix(800), encoding: .utf8)
            ?? "<non-utf8 \(data.count) bytes>"
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw UsageError.badResponse(status: status, body: body)
        }
        let windows = try CursorUsageSnapshotParser.parse(data)
        guard !windows.isEmpty else { throw UsageError.noWindows(body: body) }
        return UsageReading(windows: windows)
    }
}
