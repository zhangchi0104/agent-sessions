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

/// Reduces OAuth endpoint failures to an operation label plus a small,
/// structured error code. Raw authentication responses may contain sensitive
/// details and must never flow into diagnostics or user-visible errors.
nonisolated enum OAuthErrorDiagnostics {
    static func summary(_ data: Data, operation: String) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return operation
        }

        var codes: [String] = []
        collectCodes(from: root, depth: 0, into: &codes)
        guard let code = codes.first else { return operation }
        return "\(operation) (\(code))"
    }

    private static func collectCodes(
        from value: Any,
        depth: Int,
        into codes: inout [String]
    ) {
        guard depth <= 6 else { return }
        if let object = value as? [String: Any] {
            for (key, child) in object {
                if ["error", "code", "error_code", "type"].contains(key),
                   let raw = child as? String,
                   let code = normalizedCode(raw),
                   !codes.contains(code) {
                    codes.append(code)
                }
                if child is [String: Any] || child is [Any] {
                    collectCodes(from: child, depth: depth + 1, into: &codes)
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectCodes(from: child, depth: depth + 1, into: &codes)
            }
        }
    }

    private static func normalizedCode(_ raw: String) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized.count <= 80 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._")
        return normalized.unicodeScalars.allSatisfy(allowed.contains) ? normalized : nil
    }
}

/// Ownership of the per-credential refresh critical section. Production
/// Keychain stores back this with an inter-process file lock; in-memory test
/// stores use the no-op default below. Callers must keep the lease alive while
/// re-reading and mutating the credential store, then release it explicitly.
nonisolated protocol RefreshCoordinationLease: AnyObject, Sendable {
    func release()
}

nonisolated private final class UncoordinatedRefreshLease: RefreshCoordinationLease {
    func release() {}
}

/// Where one Coding Agent's OAuth tokens live between launches. `AgentTokenCache`
/// talks to this rather than the Keychain directly, so it can be exercised in
/// tests without touching the user's real Keychain.
protocol TokenStore {
    func save(_ tokens: OAuthTokens) throws
    /// `.success(nil)` means there is no stored account. `.failure` means the
    /// store could not be read and the answer is *unknown* — which is not the
    /// same thing, and must not be cached as "signed out".
    func load() -> Result<OAuthTokens?, Error>
    /// Remove the durable credential. A caller must not publish "signed out"
    /// until this succeeds (or the store reports that no item exists).
    func clear() throws
    /// Serialize refresh-token ownership across app processes. Refresh, login
    /// adoption, and sign-out all take the same account-scoped lease so none can
    /// overwrite a credential another process changed while a request awaited.
    func acquireRefreshCoordination() async throws -> any RefreshCoordinationLease
}

extension TokenStore {
    func acquireRefreshCoordination() async throws -> any RefreshCoordinationLease {
        UncoordinatedRefreshLease()
    }
}

extension KeychainTokenStore: TokenStore {}

/// The OAuth server accepted a refresh and the live token pair is already in
/// memory, but persisting that rotated pair failed. This deliberately carries
/// no underlying error text or credential material; callers only need to know
/// that the current launch can continue while durable storage needs attention.
nonisolated struct RefreshedTokenPersistenceError: Error, Equatable, Sendable {
}

/// The refresh grant was accepted (and any rotated fields were adopted), but
/// the response did not provide a usable access token and the inherited one is
/// already expired. This is session proof, not revocation; Usage must wait for
/// a later refresh instead of sending the expired bearer.
nonisolated struct RefreshedAccessTokenUnavailableError: Error, Equatable, Sendable {
    let credentialsPersisted: Bool
}

/// Reading the credential store can fail transiently (for example while the
/// login Keychain is locked). That is neither a stored account nor proof that
/// no account exists, so coordinators must keep the last-known presentation
/// and retry later.
nonisolated enum CredentialPresence: Equatable, Sendable {
    case present
    case absent
    case temporarilyUnavailable
}

/// Sanitized store error used across the auth/UI boundary. The underlying
/// Keychain status and item data intentionally never enter diagnostics.
nonisolated struct CredentialStoreUnavailableError: Error, Equatable, Sendable {
}

/// What one Coding Agent's OAuth session offers the rest of the app.
protocol AgentAuthSession: AnyObject {
    var isSignedIn: Bool { get }
    var credentialPresence: CredentialPresence { get }
    /// Whether startup/manual checks can prove refresh-token validity now,
    /// rather than waiting for the access token's local expiry.
    var supportsProactiveSessionValidation: Bool { get }
    /// Monotonically advances whenever the refresh endpoint accepts this
    /// session. The coordinator samples it around a provider request so a
    /// natural expiry refresh can prove validity even when the subsequent
    /// Usage request fails or its 200 response is not itself refresh proof.
    var refreshValidationRevision: Int { get }
    /// True while the current in-memory rotated pair has not yet reached the
    /// durable store. Usage may continue with a fresh bearer, but diagnostics
    /// must retain the warning and another rotation must wait for persistence.
    var hasPendingTokenPersistence: Bool { get }
    /// A valid bearer token, refreshing first if the stored one has expired.
    func validAccessToken() async throws -> String
    /// Rotate the stored token pair even when the access token has not expired.
    /// Only sessions advertising `supportsProactiveSessionValidation` are asked
    /// to do this by the coordinator.
    func forceRefreshAccessToken() async throws -> String
    /// The account id some usage endpoints want as a header; nil when the
    /// agent's endpoint doesn't take one.
    func accountID() -> String?
    /// Hold this account's refresh critical section across a planned app
    /// relaunch. The old process first waits for any accepted rotation to be
    /// durable; the replacement then cannot validate until the predecessor has
    /// terminated and released the lease.
    func acquireRelaunchCoordination() async throws -> any RefreshCoordinationLease
    func signOut() async throws

    /// Open the browser to sign in. A `.selfCompleting` agent's sign-in is
    /// finished when this returns; a `.pasteCode` agent's returns as soon as the
    /// browser is open, and finishes in `completeSignIn(pastedCode:)`.
    func beginSignIn() async throws
    /// Locale-aware entry point used by the app. Existing test doubles and
    /// integrations can rely on the default bridge to `beginSignIn()`.
    func beginSignIn(localizer: AppLocalizer) async throws
    /// Exchange the code the user pasted back for tokens.
    func completeSignIn(pastedCode: String) async throws
    /// Locale-aware entry point used by the app for paste-code validation and
    /// unsupported-flow errors.
    func completeSignIn(pastedCode: String, localizer: AppLocalizer) async throws
}

extension AgentAuthSession {
    var credentialPresence: CredentialPresence { isSignedIn ? .present : .absent }
    var supportsProactiveSessionValidation: Bool { false }
    var refreshValidationRevision: Int { 0 }
    var hasPendingTokenPersistence: Bool { false }

    func forceRefreshAccessToken() async throws -> String {
        try await validAccessToken()
    }

    func acquireRelaunchCoordination() async throws -> any RefreshCoordinationLease {
        UncoordinatedRefreshLease()
    }

    func beginSignIn(localizer: AppLocalizer) async throws {
        try await beginSignIn()
    }

    /// Agents that don't use the paste-a-code flow never see a pasted code —
    /// the UI only offers the field to the ones whose `signInStyle` asks for it.
    func completeSignIn(pastedCode: String) async throws {
        throw UsageError.loginFailed(
            AppLocalizer(locale: .current).localized(
                LocalizedStringResource.accountSignInErrorPastedCodeUnsupported
            )
        )
    }

    func completeSignIn(pastedCode: String, localizer: AppLocalizer) async throws {
        throw UsageError.loginFailed(
            localizer.localized(
                LocalizedStringResource.accountSignInErrorPastedCodeUnsupported
            )
        )
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
    /// Expiry refresh and proactive validation share one rotation. Refresh
    /// grants are single-use, so concurrent requests must never send the same
    /// stored refresh token twice.
    private var refreshFlight: (id: Int, task: Task<OAuthTokens, Error>)?
    private var nextRefreshFlightID = 0
    /// Bumped whenever ownership of the cached account changes. A refresh
    /// captures it before awaiting and re-checks after, so sign-out or a newer
    /// sign-in that lands mid-flight always wins.
    private var signOutGeneration = 0
    /// A definitive refresh rejection quarantines the old access token too.
    /// It may still be locally unexpired, but it belongs to a refresh grant the
    /// server has declared unusable and must never be emitted again.
    private var terminalRefreshFailure: OAuthRefreshError?
    /// The server has already accepted this rotated pair, but the durable write
    /// failed. `replacing` is the exact credential observed under the account
    /// lease before rotation; it makes retries compare-and-replace rather than
    /// overwriting a newer login, rotation, or sign-out from another process.
    private var pendingTokenPersistence: (tokens: OAuthTokens, replacing: OAuthTokens)?
    /// Successful refresh responses are session-validity proof independently
    /// of whether the following Usage request succeeds.
    private(set) var refreshValidationRevision = 0

    var hasPendingTokenPersistence: Bool { pendingTokenPersistence != nil }

    init(store: any TokenStore,
         now: @escaping () -> Date = Date.init,
         refreshTokens: @escaping (OAuthTokens) async throws -> OAuthTokens) {
        self.store = store
        self.now = now
        self.refreshTokens = refreshTokens
    }

    var tokens: OAuthTokens? {
        _ = credentialPresence
        return cached
    }

    var credentialPresence: CredentialPresence {
        if !loaded {
            switch store.load() {
            case .success(let stored):
                cached = stored
                loaded = true
            case .failure:
                // Leave `loaded` false so a later timer/manual action retries
                // the Keychain instead of latching a transient read failure.
                cached = nil
                return .temporarilyUnavailable
            }
        }
        return cached == nil ? .absent : .present
    }

    var isSignedIn: Bool { credentialPresence == .present }

    /// Take ownership of freshly minted tokens at the end of a login. A new
    /// login replaces the current account only after its credential can be
    /// stored; unlike a refresh, no single-use predecessor has already been
    /// consumed, so publishing an undurable in-memory login would leave the UI
    /// and Keychain describing different accounts.
    func adopt(
        _ tokens: OAuthTokens,
        ifCurrent loginIsCurrent: () -> Bool
    ) async throws {
        let lease = try await store.acquireRefreshCoordination()
        defer { lease.release() }
        // OAuth completion checks made by the owning AuthSession before this
        // await are no longer authoritative: sign-out or a newer login may
        // have invalidated the attempt while it waited for another process's
        // credential operation. Re-check under the lease immediately before
        // the first durable mutation so an old flow cannot resurrect tokens.
        guard loginIsCurrent() else { throw UsageError.notSignedIn }
        try store.save(tokens)
        refreshFlight?.task.cancel()
        refreshFlight = nil
        signOutGeneration += 1
        terminalRefreshFailure = nil
        pendingTokenPersistence = nil
        cached = tokens
        loaded = true
    }

    func signOut() async throws {
        let lease = try await store.acquireRefreshCoordination()
        defer { lease.release() }
        // Clear durable state first. If the Keychain refuses the delete, keep
        // the in-memory account and let the UI report that sign-out did not
        // complete; otherwise the old item would silently reappear on launch.
        try store.clear()
        refreshFlight?.task.cancel()
        refreshFlight = nil
        cached = nil
        loaded = true
        signOutGeneration += 1
        terminalRefreshFailure = nil
        pendingTokenPersistence = nil
    }

    /// A valid bearer token, refreshing first if the stored one has expired. A
    /// failed refresh throws rather than clearing the session: the tokens may
    /// still be good and the network may not be, and silently reading as signed
    /// out would make the user reconnect for nothing.
    func validAccessToken() async throws -> String {
        guard var current = tokens else { throw UsageError.notSignedIn }
        let generation = signOutGeneration
        if pendingTokenPersistence != nil {
            // A normal Usage call is a safe opportunity to make the already
            // accepted pair durable. Failure does not withhold a still-fresh
            // bearer, but the debt remains visible and blocks another rotation.
            try? await retryPendingTokenPersistence(generation: generation)
            guard generation == signOutGeneration,
                  let reconciled = cached else { throw UsageError.notSignedIn }
            current = reconciled
        }
        if let terminalRefreshFailure { throw terminalRefreshFailure }
        if refreshFlight != nil {
            do {
                current = try await refresh(current)
            } catch let error as OAuthRefreshError
                where error.reauthenticationReason == nil
                    && !current.isExpired(at: now())
                    && generation == signOutGeneration
                    && terminalRefreshFailure == nil {
                // A normal caller that joined a proactive check may continue
                // with its still-fresh access token after a transient check
                // failure. Terminal and persistence failures never fall back.
                return current.accessToken
            }
            return current.accessToken
        }
        if current.isExpired(at: now()) {
            current = try await refresh(current)
        }
        return current.accessToken
    }

    /// Proactively prove that the refresh grant is still valid. This shares the
    /// same generation guard as expiry refresh so a concurrent user sign-out
    /// always wins and the rotated pair can never resurrect cleared credentials.
    func forceRefreshAccessToken() async throws -> String {
        guard let current = tokens else { throw UsageError.notSignedIn }
        if let terminalRefreshFailure { throw terminalRefreshFailure }
        return try await refresh(current).accessToken
    }

    /// Quiesce this credential before a planned process handoff. Acquiring the
    /// same lease as refresh waits for an existing network rotation and its
    /// Keychain write. Reconciliation also retries an undurable rotated pair;
    /// if that write still fails, relaunch must be cancelled because killing
    /// this process would discard the only usable refresh token.
    func acquireRelaunchCoordination() async throws -> any RefreshCoordinationLease {
        let generation = signOutGeneration
        let lease: any RefreshCoordinationLease
        do {
            lease = try await store.acquireRefreshCoordination()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CredentialStoreUnavailableError()
        }

        do {
            guard generation == signOutGeneration else { throw UsageError.notSignedIn }
            var persisted = try loadPersistedCredential()
            if pendingTokenPersistence != nil {
                persisted = try resolvePendingTokenPersistence(
                    against: persisted,
                    generation: generation
                )
            }
            guard generation == signOutGeneration else { throw UsageError.notSignedIn }

            if persisted != cached {
                cached = persisted
                loaded = true
                terminalRefreshFailure = nil
            }
            return lease
        } catch {
            lease.release()
            throw error
        }
    }

    private func refresh(_ current: OAuthTokens) async throws -> OAuthTokens {
        let generation = signOutGeneration
        let flight: (id: Int, task: Task<OAuthTokens, Error>)
        if let existing = refreshFlight {
            flight = existing
        } else {
            let id = nextRefreshFlightID
            nextRefreshFlightID += 1
            let task = Task {
                let lease: any RefreshCoordinationLease
                do {
                    lease = try await store.acquireRefreshCoordination()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw CredentialStoreUnavailableError()
                }
                defer { lease.release() }
                guard generation == signOutGeneration else { throw UsageError.notSignedIn }

                var persisted = try loadPersistedCredential()
                if pendingTokenPersistence != nil {
                    persisted = try resolvePendingTokenPersistence(
                        against: persisted,
                        generation: generation
                    )
                }
                guard generation == signOutGeneration else { throw UsageError.notSignedIn }
                guard let coordinatedCurrent = persisted else {
                    // Another process explicitly removed this account while we
                    // waited. Converge locally instead of restoring it.
                    cached = nil
                    loaded = true
                    terminalRefreshFailure = nil
                    pendingTokenPersistence = nil
                    throw UsageError.notSignedIn
                }

                if coordinatedCurrent != current {
                    // The lock winner already rotated or replaced the durable
                    // credential. Its write is the result this caller was
                    // waiting for; adopt it and never replay the stale grant.
                    cached = coordinatedCurrent
                    loaded = true
                    terminalRefreshFailure = nil
                    pendingTokenPersistence = nil
                    if !coordinatedCurrent.isExpired(at: now()) {
                        refreshValidationRevision &+= 1
                        return coordinatedCurrent
                    }
                }

                let refreshed: OAuthTokens
                do {
                    refreshed = try await refreshTokens(coordinatedCurrent)
                } catch let error as OAuthRefreshError {
                    if generation == signOutGeneration,
                       error.reauthenticationReason != nil {
                        terminalRefreshFailure = error
                    }
                    throw error
                }
                // The refresh released the main actor for a network round trip,
                // so account ownership may have changed while it was in flight.
                guard generation == signOutGeneration else { throw UsageError.notSignedIn }
                refreshValidationRevision &+= 1
                terminalRefreshFailure = nil
                cached = refreshed
                var credentialsPersisted = true
                if refreshed != coordinatedCurrent {
                    do {
                        try store.save(refreshed)
                        pendingTokenPersistence = nil
                    } catch {
                        // Keep the exact predecessor so a retry cannot overwrite
                        // a newer cross-process login, rotation, or sign-out.
                        pendingTokenPersistence = (
                            tokens: refreshed,
                            replacing: coordinatedCurrent
                        )
                        credentialsPersisted = false
                    }
                } else {
                    pendingTokenPersistence = nil
                }
                guard !refreshed.isExpired(at: now()) else {
                    throw RefreshedAccessTokenUnavailableError(
                        credentialsPersisted: credentialsPersisted
                    )
                }
                if !credentialsPersisted {
                    throw RefreshedTokenPersistenceError()
                }
                return refreshed
            }
            flight = (id, task)
            refreshFlight = flight
        }

        defer {
            if refreshFlight?.id == flight.id { refreshFlight = nil }
        }
        return try await flight.task.value
    }

    /// Retry a debt without consuming another refresh grant. The compare step
    /// occurs under the same inter-process lease as refresh/adopt/sign-out.
    private func retryPendingTokenPersistence(generation: Int) async throws {
        let lease: any RefreshCoordinationLease
        do {
            lease = try await store.acquireRefreshCoordination()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CredentialStoreUnavailableError()
        }
        defer { lease.release() }
        guard generation == signOutGeneration else { throw UsageError.notSignedIn }
        let persisted = try loadPersistedCredential()
        let reconciled = try resolvePendingTokenPersistence(
            against: persisted,
            generation: generation
        )
        guard generation == signOutGeneration else { throw UsageError.notSignedIn }
        cached = reconciled
        loaded = true
        if reconciled == nil { terminalRefreshFailure = nil }
    }

    private func loadPersistedCredential() throws -> OAuthTokens? {
        switch store.load() {
        case .success(let tokens):
            return tokens
        case .failure:
            throw CredentialStoreUnavailableError()
        }
    }

    /// Compare-and-replace the failed write. A different durable value means a
    /// lock holder already published a newer credential (or removed it), so the
    /// stale debt must never overwrite that state.
    private func resolvePendingTokenPersistence(
        against persisted: OAuthTokens?,
        generation: Int
    ) throws -> OAuthTokens? {
        guard generation == signOutGeneration else { throw UsageError.notSignedIn }
        guard let pending = pendingTokenPersistence else { return persisted }
        if persisted == pending.tokens {
            pendingTokenPersistence = nil
            return pending.tokens
        }
        if persisted == pending.replacing {
            do {
                try store.save(pending.tokens)
                pendingTokenPersistence = nil
                return pending.tokens
            } catch {
                throw RefreshedTokenPersistenceError()
            }
        }

        // A different durable credential is already a successful persistence
        // outcome for the account; nil is an explicit cross-process sign-out.
        pendingTokenPersistence = nil
        terminalRefreshFailure = nil
        return persisted
    }

    func accountID() -> String? { tokens?.accountID }
}
