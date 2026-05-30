//
//  OAuthClient.swift
//  TokenStats
//
//  Thin I/O shell around OAuthFlow: opens the browser and POSTs token
//  requests. All pure logic lives in OAuthFlow.
//

import Foundation
import AppKit

struct OAuthClient {
    var session: URLSession = .shared

    func openAuthorizePage(pkce: PKCE, state: String) {
        NSWorkspace.shared.open(OAuthFlow.authorizeURL(pkce: pkce, state: state))
    }

    func exchangeCode(_ code: String, verifier: String, state: String) async throws -> OAuthTokens {
        try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthFlow.redirectURI,
            "client_id": OAuthFlow.clientID,
            "code_verifier": verifier,
            "state": state,
        ])
    }

    func refresh(refreshToken: String) async throws -> OAuthTokens {
        try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthFlow.clientID,
        ])
    }

    private func postToken(_ body: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: OAuthFlow.tokenEndpoint)
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let body = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UsageError.badResponse(status: (response as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }
        return try OAuthFlow.parseTokens(data)
    }
}
