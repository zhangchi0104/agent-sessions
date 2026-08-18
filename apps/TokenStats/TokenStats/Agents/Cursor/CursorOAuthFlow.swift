//
//  CursorOAuthFlow.swift
//  TokenStats
//
//  Pure helpers for Cursor's browser-login polling flow and refresh response.
//  The contract is unofficial; see docs/cursor-integration.md and ADR-0010.
//

import Foundation

enum CursorOAuthFlow {
    static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    static let authorizeEndpoint = URL(string: "https://cursor.com/loginDeepControl")!
    static let pollEndpoint = URL(string: "https://api2.cursor.sh/auth/poll")!
    static let tokenEndpoint = URL(string: "https://api2.cursor.sh/oauth/token")!

    static func authorizeURL(pkce: PKCE, uuid: String) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "challenge", value: pkce.challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
            URLQueryItem(name: "redirectTarget", value: "cli"),
        ]
        return components.url!
    }

    static func pollURL(verifier: String, uuid: String) -> URL {
        var components = URLComponents(url: pollEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "verifier", value: verifier),
        ]
        return components.url!
    }

    static func parsePollTokens(_ data: Data, now: Date = Date()) throws -> OAuthTokens {
        struct Raw: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return OAuthTokens(
            accessToken: raw.accessToken,
            refreshToken: raw.refreshToken,
            expiresAt: expiration(of: raw.accessToken, now: now)
        )
    }

    static func parseRefreshTokens(
        _ data: Data,
        previous: OAuthTokens,
        now: Date = Date()
    ) throws -> OAuthTokens {
        struct Raw: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let expiresAt = raw.expires_in.map { now.addingTimeInterval($0) }
            ?? expiration(of: raw.access_token, now: now)
        return OAuthTokens(
            accessToken: raw.access_token,
            // Cursor's current client treats a refresh response's access token
            // as the next refresh credential when no separate one is returned.
            refreshToken: raw.refresh_token ?? raw.access_token,
            expiresAt: expiresAt,
            accountID: previous.accountID
        )
    }

    private static func expiration(of accessToken: String, now: Date) -> Date {
        let parts = accessToken.split(separator: ".")
        if parts.count >= 2,
           let payload = Data(base64URLEncoded: String(parts[1])),
           let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let seconds = (json["exp"] as? NSNumber)?.doubleValue,
           seconds.isFinite,
           seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        // Cursor's response does not otherwise state access-token lifetime.
        // A short fallback makes the refresh path conservative.
        return now.addingTimeInterval(60 * 60)
    }
}
