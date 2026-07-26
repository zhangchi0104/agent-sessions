//
//  CodexOAuthClient.swift
//  TokenStats
//
//  Thin I/O shell around CodexOAuthFlow: opens the browser and POSTs token
//  requests to auth.openai.com. The Codex token endpoint takes
//  form-urlencoded bodies (unlike Claude Code's JSON). All pure logic lives in
//  CodexOAuthFlow.
//

import Foundation
import AppKit

struct CodexOAuthClient {
    var session: URLSession = .shared

    func openAuthorizePage(pkce: PKCE, state: String, redirectURI: String) {
        NSWorkspace.shared.open(
            CodexOAuthFlow.authorizeURL(pkce: pkce, state: state, redirectURI: redirectURI)
        )
    }

    func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> OAuthTokens {
        try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": CodexOAuthFlow.clientID,
            "code_verifier": verifier,
        ])
    }

    /// Refresh rotates the token; carry forward the prior refresh token and
    /// account id when the response omits them.
    func refresh(tokens previous: OAuthTokens) async throws -> OAuthTokens {
        var refreshed = try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": previous.refreshToken,
            "client_id": CodexOAuthFlow.clientID,
            "scope": CodexOAuthFlow.scopes,
        ])
        if refreshed.refreshToken.isEmpty { refreshed.refreshToken = previous.refreshToken }
        if refreshed.accountID == nil { refreshed.accountID = previous.accountID }
        return refreshed
    }

    private func postToken(_ body: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: CodexOAuthFlow.tokenEndpoint)
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formURLEncoded(body).utf8)

        let (data, response) = try await session.data(for: request)
        let bodyText = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UsageError.badResponse(status: (response as? HTTPURLResponse)?.statusCode ?? -1, body: bodyText)
        }
        return try CodexOAuthFlow.parseTokens(data)
    }

    private func formURLEncoded(_ body: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return body
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
