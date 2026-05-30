//
//  CodexOAuthFlow.swift
//  TokenStats
//
//  Pure OAuth helpers for the Codex Coding Agent — authorize-URL construction,
//  token-response parsing, and id_token account-id extraction. Network, browser,
//  and the loopback listener live in CodexOAuthClient.
//
//  Unlike Claude Code's paste-the-code flow (OAuthFlow), Codex uses OpenAI's
//  public CLI client with a loopback redirect (see docs/codex-integration.md
//  and ADR-0002). Parameters are unofficial and read from the open-source
//  openai/codex CLI; the originator value and the exact account-id claim path
//  still want live confirmation.
//

import Foundation

enum CodexOAuthFlow {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let issuer = "https://auth.openai.com"
    static let authorizeEndpoint = URL(string: "https://auth.openai.com/oauth/authorize")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    static let scopes = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    /// The Codex CLI tags its login with this originator; we reuse it since we
    /// authenticate with the same public client. To confirm against live traffic.
    static let originator = "codex_cli_rs"

    /// The loopback callback the CLI registers; the port is chosen at runtime.
    static func redirectURI(port: UInt16) -> String {
        "http://localhost:\(port)/auth/callback"
    }

    static func authorizeURL(pkce: PKCE, state: String, redirectURI: String) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: originator),
        ]
        return components.url!
    }

    /// Parse a token response. `refresh_token` and `id_token` are optional
    /// because a refresh response may omit a rotated refresh token or id_token;
    /// callers carry the previous values forward when these come back empty.
    static func parseTokens(_ data: Data, now: Date = Date()) throws -> OAuthTokens {
        struct Raw: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
            let id_token: String?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return OAuthTokens(
            accessToken: raw.access_token,
            refreshToken: raw.refresh_token ?? "",
            expiresAt: now.addingTimeInterval(raw.expires_in),
            accountID: raw.id_token.flatMap(accountID(fromIDToken:))
        )
    }

    /// Pull the ChatGPT account id out of the id_token's claims. The CLI reads
    /// it from the `https://api.openai.com/auth` claim; we also tolerate a
    /// top-level claim. Returns nil if the token can't be decoded or the claim
    /// is absent — the usage call then simply omits the account header.
    static func accountID(fromIDToken idToken: String) -> String? {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2,
              let payload = Data(base64URLEncoded: String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }

        if let auth = json["https://api.openai.com/auth"] as? [String: Any],
           let id = auth["chatgpt_account_id"] as? String {
            return id
        }
        return json["chatgpt_account_id"] as? String
    }
}
