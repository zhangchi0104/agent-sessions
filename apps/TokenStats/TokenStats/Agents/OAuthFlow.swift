//
//  OAuthFlow.swift
//  TokenStats
//
//  Pure OAuth helpers — PKCE generation, authorize-URL construction, and token
//  response parsing. Network and browser side-effects live in OAuthClient.
//  Parameters are unofficial; see docs/claude-code-integration.md and ADR-0001.
//

import Foundation
import CryptoKit

struct OAuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    /// Codex only: the ChatGPT account id parsed from the id_token, sent as the
    /// `ChatGPT-Account-Id` header on the usage call. nil for Claude Code and
    /// for tokens stored before this field existed (decodes as nil).
    var accountID: String?

    init(accessToken: String, refreshToken: String, expiresAt: Date, accountID: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
    }

    /// True once we're within a minute of expiry — refresh proactively.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

struct PKCE: Equatable {
    let verifier: String
    let challenge: String
}

enum OAuthFlow {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeEndpoint = URL(string: "https://claude.com/cai/oauth/authorize")!
    static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static let scopes = "org:create_api_key user:profile user:inference"

    static func makePKCE() -> PKCE {
        let verifier = randomURLSafeString(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCE(verifier: verifier, challenge: Data(digest).base64URLEncodedString())
    }

    static func makeState() -> String { randomURLSafeString(byteCount: 32) }

    static func authorizeURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// The paste-the-code callback surfaces `code#state`; split them apart.
    static func splitPastedCode(_ pasted: String) -> (code: String, state: String?) {
        let parts = pasted.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1)
        let code = String(parts.first ?? "")
        let state = parts.count > 1 ? String(parts[1]) : nil
        return (code, state)
    }

    static func parseTokens(_ data: Data, now: Date = Date()) throws -> OAuthTokens {
        struct Raw: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return OAuthTokens(
            accessToken: raw.access_token,
            refreshToken: raw.refresh_token,
            expiresAt: now.addingTimeInterval(raw.expires_in)
        )
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decode the base64url encoding produced by `base64URLEncodedString()`
    /// (used to read JWT id_token segments).
    init?(base64URLEncoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }
}
