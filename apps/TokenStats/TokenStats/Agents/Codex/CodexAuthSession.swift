//
//  CodexAuthSession.swift
//  TokenStats
//
//  Owns TokenStats' independent ChatGPT/OpenAI OAuth identity for Codex
//  (ADR-0002), persisted to its OWN keychain entry (account "codex", never
//  Claude Code's). Never reads or refreshes Codex's own ~/.codex/auth.json.
//  Caching, sign-out, and the refresh-on-expiry path come from the shared
//  AgentTokenCache; what stays here is the loopback login.
//

import Foundation

final class CodexAuthSession: AgentAuthSession {
    private let cache: AgentTokenCache
    private let client: CodexOAuthClient

    init(store: any TokenStore = KeychainTokenStore(account: "codex"),
         client: CodexOAuthClient = CodexOAuthClient(),
         now: @escaping () -> Date = Date.init) {
        self.client = client
        self.cache = AgentTokenCache(store: store, now: now) { expired in
            try await client.refresh(tokens: expired)
        }
    }

    var isSignedIn: Bool { cache.isSignedIn }

    func validAccessToken() async throws -> String { try await cache.validAccessToken() }

    /// The ChatGPT account id for the usage header, from the most recent tokens.
    func accountID() -> String? { cache.accountID() }

    func signOut() { cache.signOut() }

    /// One-shot loopback login: bind a port, open the browser, await the
    /// redirect, exchange the code, and store the tokens. Unlike the
    /// paste-a-code flow, this returns only once sign-in is complete.
    func beginSignIn() async throws {
        let listener = try LoopbackAuthListener()
        defer { listener.cancel() }
        let port = try await listener.start()
        let redirectURI = CodexOAuthFlow.redirectURI(port: port)
        let pkce = OAuthFlow.makePKCE()
        let state = OAuthFlow.makeState()

        client.openAuthorizePage(pkce: pkce, state: state, redirectURI: redirectURI)
        let callback = try await listener.waitForCallback()
        guard callback.state == state else {
            throw UsageError.loginFailed("State mismatch — possible interference; try again.")
        }
        let tokens = try await client.exchangeCode(
            callback.code, verifier: pkce.verifier, redirectURI: redirectURI
        )
        // Without a refresh token we can't keep the session alive past the
        // short-lived access token; surface that now instead of appearing
        // signed in and silently failing on the first refresh.
        guard !tokens.refreshToken.isEmpty else {
            throw UsageError.loginFailed("Sign-in did not return a refresh token; cannot stay signed in.")
        }
        try cache.adopt(tokens)
    }
}
