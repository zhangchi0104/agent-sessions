//
//  AgentTokenCacheTests.swift
//  TokenStatsTests
//
//  The auth half both Coding Agents share: hand back the stored token, refresh
//  it once it is near expiry, and never quietly downgrade a failed refresh into
//  a signed-out session. The clock is injected so expiry is exercised without
//  waiting, and the store is in-memory so nothing touches the real Keychain.
//

import Testing
import Foundation
@testable import TokenStats

@MainActor
struct AgentTokenCacheTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func tokens(access: String, expiresIn: TimeInterval,
                        refresh: String = "r0") -> OAuthTokens {
        OAuthTokens(accessToken: access, refreshToken: refresh,
                    expiresAt: now.addingTimeInterval(expiresIn))
    }

    @Test func unexpiredTokenIsReturnedAsIs() async throws {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let refresher = Refresher()
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: refresher.run)

        #expect(try await cache.validAccessToken() == "fresh")
        #expect(refresher.callCount == 0)
    }

    @Test func tokenInsideTheExpiryMarginCountsAsExpired() async throws {
        // Expiry is proactive: a token with 30s left is refreshed now rather
        // than handed out and failing mid-request.
        let store = MemoryTokenStore(tokens(access: "nearly", expiresIn: 30))
        let refresher = Refresher(next: tokens(access: "renewed", expiresIn: 3600))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: refresher.run)

        #expect(try await cache.validAccessToken() == "renewed")
        #expect(refresher.callCount == 1)
    }

    @Test func expiredTokenTriggersExactlyOneRefresh() async throws {
        let store = MemoryTokenStore(tokens(access: "stale", expiresIn: -60))
        let refresher = Refresher(next: tokens(access: "renewed", expiresIn: 3600))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: refresher.run)

        #expect(try await cache.validAccessToken() == "renewed")
        #expect(refresher.callCount == 1)

        // The renewed token was cached and persisted, so a second read spends
        // no further refresh.
        #expect(try await cache.validAccessToken() == "renewed")
        #expect(refresher.callCount == 1)
        #expect(store.saved?.accessToken == "renewed")
    }

    @Test func failedRefreshSurfacesTheErrorAndStaysSignedIn() async {
        let store = MemoryTokenStore(tokens(access: "stale", expiresIn: -60))
        let refresher = Refresher(failure: UsageError.badResponse(status: 503, body: "down"))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: refresher.run)

        await #expect(throws: UsageError.self) { try await cache.validAccessToken() }
        // The token may still be good and the network may not be; reading as
        // signed out here would make the user reconnect for nothing.
        #expect(cache.isSignedIn)
        #expect(store.cleared == false)
    }

    @Test func noStoredTokensReadsAsSignedOut() async {
        let cache = AgentTokenCache(store: MemoryTokenStore(nil), now: { now },
                                    refreshTokens: Refresher().run)

        #expect(!cache.isSignedIn)
        await #expect(throws: UsageError.self) { try await cache.validAccessToken() }
    }

    @Test func theStoreIsReadOnceAndThenServedFromMemory() async throws {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: Refresher().run)

        _ = cache.isSignedIn
        _ = try await cache.validAccessToken()
        _ = try await cache.validAccessToken()

        #expect(store.loadCount == 1)
    }

    @Test func adoptingTokensPersistsThemAndSignsIn() throws {
        let store = MemoryTokenStore(nil)
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: Refresher().run)

        try cache.adopt(tokens(access: "new", expiresIn: 3600))

        #expect(cache.isSignedIn)
        #expect(store.saved?.accessToken == "new")
    }

    @Test func signingOutClearsTheStoreAndTheMemoryCopy() async throws {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: Refresher().run)
        _ = try await cache.validAccessToken()

        cache.signOut()

        #expect(!cache.isSignedIn)
        #expect(store.cleared)
    }
}

// MARK: - Fakes

/// The token store, in memory — the real one is the user's login Keychain.
private final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private(set) var saved: OAuthTokens?
    private(set) var cleared = false
    private(set) var loadCount = 0

    init(_ initial: OAuthTokens?) { saved = initial }

    func save(_ tokens: OAuthTokens) throws { saved = tokens }

    func load() -> OAuthTokens? {
        loadCount += 1
        return saved
    }

    func clear() {
        saved = nil
        cleared = true
    }
}

/// Stands in for an agent's OAuth client, counting how often it was asked to
/// exchange an expired token.
private final class Refresher: @unchecked Sendable {
    private let next: OAuthTokens?
    private let failure: Error?
    private(set) var callCount = 0

    init(next: OAuthTokens? = nil, failure: Error? = nil) {
        self.next = next
        self.failure = failure
    }

    func run(_ expired: OAuthTokens) async throws -> OAuthTokens {
        callCount += 1
        if let failure { throw failure }
        guard let next else {
            Issue.record("The cache refreshed a token this test expected it to hand back as-is")
            return expired
        }
        return next
    }
}
