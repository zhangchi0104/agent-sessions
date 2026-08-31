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

nonisolated enum CodexOAuthFlow {
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

    /// Parse the authorization-code exchange. A new login must provide an
    /// access token and lifetime; refresh responses use the more tolerant
    /// parser below because the server may return only the fields it rotated.
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

    /// Parse an accepted refresh grant without discarding a rotated token just
    /// because another field was omitted. The current Codex service treats all
    /// token fields as optional on refresh; absent values inherit the previous
    /// credential. When `expires_in` is absent, prefer the new access JWT's
    /// `exp`, then retain the previous expiry as the final compatibility path.
    static func parseRefreshTokens(
        _ data: Data,
        previous: OAuthTokens,
        now: Date = Date()
    ) throws -> OAuthTokens {
        struct Raw: Decodable {
            let access_token: String?
            let refresh_token: String?
            let expires_in: Double?
            let id_token: String?
        }

        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let accessToken = nonempty(raw.access_token) ?? previous.accessToken
        let refreshToken = nonempty(raw.refresh_token) ?? previous.refreshToken
        let idToken = nonempty(raw.id_token)
        let refreshedAccessToken = nonempty(raw.access_token)
        let containsAcceptedField = refreshedAccessToken != nil
            || nonempty(raw.refresh_token) != nil
            || idToken != nil
        guard containsAcceptedField, !accessToken.isEmpty, !refreshToken.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Refresh response contained no usable token fields"
            ))
        }

        let expiresAt: Date
        if refreshedAccessToken != nil, let expiresIn = raw.expires_in {
            guard expiresIn.isFinite, expiresIn > 0 else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Invalid expires_in"
                ))
            }
            expiresAt = now.addingTimeInterval(expiresIn)
        } else if let refreshedExpiry = expirationDate(fromAccessToken: refreshedAccessToken) {
            expiresAt = refreshedExpiry
        } else {
            expiresAt = previous.expiresAt
        }

        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            accountID: idToken.flatMap(accountID(fromIDToken:)) ?? previous.accountID
        )
    }

    static func expirationDate(fromAccessToken accessToken: String?) -> Date? {
        guard let accessToken else { return nil }
        let segments = accessToken.split(separator: ".")
        guard segments.count >= 2,
              let payload = Data(base64URLEncoded: String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }

        if let seconds = json["exp"] as? Double {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = json["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return nil
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
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
