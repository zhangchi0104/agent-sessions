//
//  ClaudeCodeAuthSession.swift
//  TokenStats
//
//  Owns TokenStats' independent OAuth identity for Claude Code (ADR-0001).
//  Caching, sign-out, and the refresh-on-expiry path come from the shared
//  AgentTokenCache; what stays here is the paste-the-code login, which is
//  Claude Code's alone.
//

import Foundation

final class ClaudeCodeAuthSession: AgentAuthSession {
    private let cache: AgentTokenCache
    private let client: OAuthClient

    /// PKCE + state for an in-flight login; cleared once the code is exchanged.
    private var pending: (pkce: PKCE, state: String)?
    private var signInLocalizer = AppLocalizer(locale: .current)

    init(store: any TokenStore = KeychainTokenStore(),
         client: OAuthClient = OAuthClient(),
         now: @escaping () -> Date = Date.init) {
        self.client = client
        self.cache = AgentTokenCache(store: store, now: now) { expired in
            try await client.refresh(refreshToken: expired.refreshToken)
        }
    }

    var isSignedIn: Bool { cache.isSignedIn }

    func validAccessToken() async throws -> String { try await cache.validAccessToken() }

    func signOut() {
        cache.signOut()
        pending = nil
    }

    /// Open the browser for the user to approve; they'll paste back a code.
    func beginSignIn() async throws {
        try await beginSignIn(localizer: AppLocalizer(locale: .current))
    }

    func beginSignIn(localizer: AppLocalizer) async throws {
        signInLocalizer = localizer
        let pkce = OAuthFlow.makePKCE()
        let state = OAuthFlow.makeState()
        pending = (pkce, state)
        client.openAuthorizePage(pkce: pkce, state: state)
    }

    /// Exchange the pasted `code#state` for tokens and store them.
    func completeSignIn(pastedCode: String) async throws {
        guard let pending else { throw UsageError.notSignedIn }
        let (code, returnedState) = OAuthFlow.splitPastedCode(pastedCode)
        // When the callback appends the state (`code#state`), validate it against
        // the state we generated for this login — the OAuth CSRF protection.
        if let returnedState, returnedState != pending.state {
            throw UsageError.loginFailed(signInLocalizer.localized(
                LocalizedStringResource.accountSignInErrorStateMismatch
            ))
        }
        let tokens = try await client.exchangeCode(code, verifier: pending.pkce.verifier, state: pending.state)
        try cache.adopt(tokens)
        self.pending = nil
    }

    func completeSignIn(pastedCode: String, localizer: AppLocalizer) async throws {
        signInLocalizer = localizer
        try await completeSignIn(pastedCode: pastedCode)
    }
}
