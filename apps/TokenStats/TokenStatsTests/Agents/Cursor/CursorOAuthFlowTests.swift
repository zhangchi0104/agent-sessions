//
//  CursorOAuthFlowTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

struct CursorOAuthFlowTests {
    private func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    @Test func authorizeAndPollURLsCarryCursorPKCEParameters() throws {
        let pkce = PKCE(verifier: "verifier", challenge: "challenge")
        let authorize = CursorOAuthFlow.authorizeURL(pkce: pkce, uuid: "uuid-123")
        let authorizeItems = try #require(
            URLComponents(url: authorize, resolvingAgainstBaseURL: false)?.queryItems
        )
        func authorizeValue(_ name: String) -> String? {
            authorizeItems.first { $0.name == name }?.value
        }

        #expect(authorize.host == "cursor.com")
        #expect(authorizeValue("challenge") == "challenge")
        #expect(authorizeValue("uuid") == "uuid-123")
        #expect(authorizeValue("mode") == "login")
        #expect(authorizeValue("redirectTarget") == "cli")

        let poll = CursorOAuthFlow.pollURL(verifier: pkce.verifier, uuid: "uuid-123")
        let pollItems = try #require(
            URLComponents(url: poll, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(pollItems.first { $0.name == "verifier" }?.value == "verifier")
        #expect(pollItems.first { $0.name == "uuid" }?.value == "uuid-123")
    }

    @Test func pollTokensUseJWTExpiration() throws {
        let expiry = 2_000_000_000.0
        let jwt = "header.\(base64URL(#"{"exp":2000000000}"#)).signature"
        let data = Data(#"{"accessToken":"\#(jwt)","refreshToken":"refresh"}"#.utf8)

        let tokens = try CursorOAuthFlow.parsePollTokens(
            data,
            now: Date(timeIntervalSince1970: 1_000_000)
        )

        #expect(tokens.accessToken == jwt)
        #expect(tokens.refreshToken == "refresh")
        #expect(tokens.expiresAt == Date(timeIntervalSince1970: expiry))
    }

    @Test func refreshUsesReturnedAccessTokenAsRotatedCredential() throws {
        let previous = OAuthTokens(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: .distantPast
        )
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tokens = try CursorOAuthFlow.parseRefreshTokens(
            Data(#"{"access_token":"new-token","expires_in":7200}"#.utf8),
            previous: previous,
            now: now
        )

        #expect(tokens.accessToken == "new-token")
        #expect(tokens.refreshToken == "new-token")
        #expect(tokens.expiresAt == now.addingTimeInterval(7_200))
    }
}
