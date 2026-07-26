//
//  AgentAuthSession.swift
//  TokenStats
//
//  The auth surface every Coding Agent presents, and the half of it that does
//  not vary. Both agents cache the Keychain read, answer "am I signed in?",
//  sign out, and refresh an expired token identically; only login differs. That
//  shared half is `AgentTokenCache`, which each agent's session holds.
//

import Foundation

/// Where one Coding Agent's OAuth tokens live between launches. `AgentTokenCache`
/// talks to this rather than the Keychain directly, so it can be exercised in
/// tests without touching the user's real Keychain.
protocol TokenStore {
    func save(_ tokens: OAuthTokens) throws
    func load() -> OAuthTokens?
    func clear()
}

extension KeychainTokenStore: TokenStore {}

/// What one Coding Agent's OAuth session offers the rest of the app.
protocol AgentAuthSession: AnyObject {
    var isSignedIn: Bool { get }
    /// A valid bearer token, refreshing first if the stored one has expired.
    func validAccessToken() async throws -> String
    /// The account id some usage endpoints want as a header; nil when the
    /// agent's endpoint doesn't take one.
    func accountID() -> String?
    func signOut()

    /// Open the browser to sign in. A `.selfCompleting` agent's sign-in is
    /// finished when this returns; a `.pasteCode` agent's returns as soon as the
    /// browser is open, and finishes in `completeSignIn(pastedCode:)`.
    func beginSignIn() async throws
    /// Exchange the code the user pasted back for tokens.
    func completeSignIn(pastedCode: String) async throws
}

extension AgentAuthSession {
    /// Agents that don't use the paste-a-code flow never see a pasted code —
    /// the UI only offers the field to the ones whose `signInStyle` asks for it.
    func completeSignIn(pastedCode: String) async throws {
        throw UsageError.loginFailed("This agent does not sign in with a pasted code.")
    }

    func accountID() -> String? { nil }
}

/// The part of an agent's auth session that is the same for every agent: one
/// Keychain read per launch, held in memory, and a silent refresh once the
/// stored token is close to expiry.
///
/// The clock is injected so the expiry path can be tested without waiting.
final class AgentTokenCache {
    private let store: any TokenStore
    private let now: () -> Date
    /// How this agent exchanges an expired token for a fresh one. The two OAuth
    /// clients differ substantively, so this stays per-agent.
    private let refreshTokens: (OAuthTokens) async throws -> OAuthTokens

    /// In-memory copy so we hit the store at most once per launch, not on every
    /// refresh trigger. `loaded` distinguishes "not yet read" from "read, and
    /// there was nothing".
    private var cached: OAuthTokens?
    private var loaded = false

    init(store: any TokenStore,
         now: @escaping () -> Date = Date.init,
         refreshTokens: @escaping (OAuthTokens) async throws -> OAuthTokens) {
        self.store = store
        self.now = now
        self.refreshTokens = refreshTokens
    }

    var tokens: OAuthTokens? {
        if !loaded {
            cached = store.load()
            loaded = true
        }
        return cached
    }

    var isSignedIn: Bool { tokens != nil }

    /// Take ownership of freshly minted tokens at the end of a login.
    func adopt(_ tokens: OAuthTokens) throws {
        try store.save(tokens)
        cached = tokens
        loaded = true
    }

    func signOut() {
        store.clear()
        cached = nil
        loaded = true
    }

    /// A valid bearer token, refreshing first if the stored one has expired. A
    /// failed refresh throws rather than clearing the session: the tokens may
    /// still be good and the network may not be, and silently reading as signed
    /// out would make the user reconnect for nothing.
    func validAccessToken() async throws -> String {
        guard var current = tokens else { throw UsageError.notSignedIn }
        if current.isExpired(at: now()) {
            current = try await refreshTokens(current)
            try store.save(current)
            cached = current
        }
        return current.accessToken
    }

    func accountID() -> String? { tokens?.accountID }
}
