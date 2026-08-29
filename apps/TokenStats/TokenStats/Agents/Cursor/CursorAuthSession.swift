//
//  CursorAuthSession.swift
//  TokenStats
//
//  TokenStats' independent Cursor login. It never reads or refreshes Cursor's
//  own credentials; its token pair lives in TokenStats' "cursor" keychain item.
//

import Foundation

final class CursorAuthSession: AgentAuthSession {
    private let cache: AgentTokenCache
    private let client: CursorOAuthClient
    private var loginGeneration = 0

    init(store: any TokenStore = KeychainTokenStore(account: "cursor"),
         client: CursorOAuthClient = CursorOAuthClient(),
         now: @escaping () -> Date = Date.init) {
        self.client = client
        self.cache = AgentTokenCache(store: store, now: now) { expired in
            try await client.refresh(tokens: expired)
        }
    }

    var isSignedIn: Bool { cache.isSignedIn }

    var credentialPresence: CredentialPresence { cache.credentialPresence }

    var hasPendingTokenPersistence: Bool { cache.hasPendingTokenPersistence }

    func validAccessToken() async throws -> String { try await cache.validAccessToken() }

    func acquireRelaunchCoordination() async throws -> any RefreshCoordinationLease {
        try await cache.acquireRelaunchCoordination()
    }

    func signOut() async throws {
        loginGeneration += 1
        try await cache.signOut()
    }

    func beginSignIn() async throws {
        loginGeneration += 1
        let generation = loginGeneration
        let pkce = OAuthFlow.makePKCE()
        let uuid = UUID().uuidString.lowercased()
        client.openAuthorizePage(pkce: pkce, uuid: uuid)
        let tokens = try await client.waitForLogin(pkce: pkce, uuid: uuid)
        guard !tokens.refreshToken.isEmpty else { throw UsageError.notSignedIn }
        guard generation == loginGeneration else { throw UsageError.notSignedIn }
        try await cache.adopt(tokens, ifCurrent: {
            generation == self.loginGeneration
        })
    }
}
