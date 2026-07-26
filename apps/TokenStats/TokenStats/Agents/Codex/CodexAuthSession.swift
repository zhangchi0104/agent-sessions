//
//  CodexAuthSession.swift
//  TokenStats
//
//  Owns TokenStats' independent ChatGPT/OpenAI OAuth identity for Codex
//  (ADR-0002): runs the loopback login, persists tokens to its OWN keychain
//  entry (account "codex", never Claude Code's), and hands out a valid access
//  token + ChatGPT account id, refreshing silently on expiry. Never reads or
//  refreshes Codex's own ~/.codex/auth.json.
//

import Foundation

final class CodexAuthSession {
    private let store: KeychainTokenStore
    private let client: CodexOAuthClient

    private var cached: OAuthTokens?
    private var loaded = false

    init(store: KeychainTokenStore = KeychainTokenStore(account: "codex"),
         client: CodexOAuthClient = CodexOAuthClient()) {
        self.store = store
        self.client = client
    }

    private func currentTokens() -> OAuthTokens? {
        if !loaded {
            cached = store.load()
            loaded = true
        }
        return cached
    }

    var isSignedIn: Bool { currentTokens() != nil }

    /// One-shot loopback login: bind a port, open the browser, await the
    /// redirect, exchange the code, and store the tokens.
    func login() async throws {
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
        try store.save(tokens)
        cached = tokens
        loaded = true
    }

    func signOut() {
        store.clear()
        cached = nil
        loaded = true
    }

    /// A valid bearer token, refreshing first if the stored one has expired.
    func validAccessToken() async throws -> String {
        guard var tokens = currentTokens() else { throw UsageError.notSignedIn }
        if tokens.isExpired {
            tokens = try await client.refresh(tokens: tokens)
            try store.save(tokens)
            cached = tokens
        }
        return tokens.accessToken
    }

    /// The ChatGPT account id for the usage header, from the most recent tokens.
    func accountID() -> String? {
        currentTokens()?.accountID
    }
}
