//
//  AuthSession.swift
//  TokenStats
//
//  Owns TokenStats' independent OAuth identity (ADR-0001): runs the
//  paste-the-code login, persists tokens to the keychain, and hands out a
//  valid access token, refreshing silently on expiry.
//

import Foundation

final class AuthSession {
    private let store: KeychainTokenStore
    private let client: OAuthClient

    /// PKCE + state for an in-flight login; cleared once the code is exchanged.
    private var pending: (pkce: PKCE, state: String)?

    /// In-memory copy so we hit the keychain at most once per launch, not on
    /// every refresh trigger. `loaded` distinguishes "not yet read" from
    /// "read, and there was nothing".
    private var cached: OAuthTokens?
    private var loaded = false

    init(store: KeychainTokenStore = KeychainTokenStore(), client: OAuthClient = OAuthClient()) {
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

    /// Open the browser for the user to approve; they'll paste back a code.
    func beginLogin() {
        let pkce = OAuthFlow.makePKCE()
        let state = OAuthFlow.makeState()
        pending = (pkce, state)
        client.openAuthorizePage(pkce: pkce, state: state)
    }

    /// Exchange the pasted `code#state` for tokens and store them.
    func completeLogin(pastedCode: String) async throws {
        guard let pending else { throw UsageError.notSignedIn }
        let (code, returnedState) = OAuthFlow.splitPastedCode(pastedCode)
        // When the callback appends the state (`code#state`), validate it against
        // the state we generated for this login — the OAuth CSRF protection.
        if let returnedState, returnedState != pending.state {
            throw UsageError.loginFailed("State mismatch — possible interference; try again.")
        }
        let tokens = try await client.exchangeCode(code, verifier: pending.pkce.verifier, state: pending.state)
        try store.save(tokens)
        cached = tokens
        loaded = true
        self.pending = nil
    }

    func signOut() {
        store.clear()
        cached = nil
        loaded = true
        pending = nil
    }

    /// A valid bearer token, refreshing first if the stored one has expired.
    func validAccessToken() async throws -> String {
        guard var tokens = currentTokens() else { throw UsageError.notSignedIn }
        if tokens.isExpired {
            tokens = try await client.refresh(refreshToken: tokens.refreshToken)
            try store.save(tokens)
            cached = tokens
        }
        return tokens.accessToken
    }
}
