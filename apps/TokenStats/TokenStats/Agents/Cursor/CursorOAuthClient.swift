//
//  CursorOAuthClient.swift
//  TokenStats
//
//  I/O shell around Cursor's browser-login poll and token refresh endpoints.
//

import AppKit
import Foundation

struct CursorOAuthClient {
    var session: URLSession = .shared
    var loginTimeout: Duration = .seconds(5 * 60)
    var retryDelay: Duration = .seconds(1)

    func openAuthorizePage(pkce: PKCE, uuid: String) {
        NSWorkspace.shared.open(CursorOAuthFlow.authorizeURL(pkce: pkce, uuid: uuid))
    }

    func waitForLogin(pkce: PKCE, uuid: String) async throws -> OAuthTokens {
        let url = CursorOAuthFlow.pollURL(verifier: pkce.verifier, uuid: uuid)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: loginTimeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.timeoutInterval = min(
                20,
                max(0.001, Self.timeInterval(clock.now.duration(to: deadline)))
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError
                where error.code == .timedOut && clock.now < deadline {
                continue
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            switch status {
            case 200:
                return try CursorOAuthFlow.parsePollTokens(data)
            case 404:
                let remaining = clock.now.duration(to: deadline)
                guard remaining > .zero else { break }
                try await clock.sleep(for: min(retryDelay, remaining))
            default:
                throw UsageError.badResponse(status: status, body: bodyPreview(data))
            }
        }
        throw URLError(.timedOut)
    }

    func refresh(tokens previous: OAuthTokens) async throws -> OAuthTokens {
        var request = URLRequest(url: CursorOAuthFlow.tokenEndpoint)
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": CursorOAuthFlow.clientID,
            "refresh_token": previous.refreshToken,
        ])

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw UsageError.badResponse(status: status, body: bodyPreview(data))
        }
        return try CursorOAuthFlow.parseRefreshTokens(data, previous: previous)
    }

    private func bodyPreview(_ data: Data) -> String {
        String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
    }

    private static func timeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
