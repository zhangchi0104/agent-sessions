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

    @Test func forcedRefreshRotatesAnOtherwiseUnexpiredToken() async throws {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let refresher = Refresher(next: tokens(access: "rotated", expiresIn: 7200))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: refresher.run)

        #expect(try await cache.forceRefreshAccessToken() == "rotated")
        #expect(refresher.callCount == 1)
        #expect(store.saved?.accessToken == "rotated")
    }

    @Test func refreshCoordinationIdentityIsStableAndAccountScoped() {
        let defaultID = KeychainTokenStore().refreshCoordinationID
        let repeatedDefaultID = KeychainTokenStore(account: "default").refreshCoordinationID
        let codexID = KeychainTokenStore(account: "codex").refreshCoordinationID
        let cursorID = KeychainTokenStore(account: "cursor").refreshCoordinationID

        #expect(defaultID == repeatedDefaultID)
        #expect(Set([defaultID, codexID, cursorID]).count == 3)
        #expect([defaultID, codexID, cursorID].allSatisfy { id in
            id.count == 64 && id.allSatisfy(\.isHexDigit)
        })
    }

    @Test func concurrentCachesShareOneCrossProcessRotation() async throws {
        let original = tokens(access: "old-access", expiresIn: 3600, refresh: "old-refresh")
        let rotated = tokens(
            access: "rotated-access",
            expiresIn: 7200,
            refresh: "rotated-refresh"
        )
        let store = CoordinatedTokenStore(original)
        let winningRefresher = ControlledRefresher(next: rotated)
        let waitingRefresher = Refresher(failure: UnexpectedRefresh())
        let winner = AgentTokenCache(store: store, now: { now }) { tokens in
            try await winningRefresher.run(tokens)
        }
        let waiter = AgentTokenCache(
            store: store,
            now: { now },
            refreshTokens: waitingRefresher.run
        )

        // Both processes cached the same predecessor before either starts.
        #expect(winner.tokens == original)
        #expect(waiter.tokens == original)

        let winningRefresh = Task { try await winner.forceRefreshAccessToken() }
        await winningRefresher.waitUntilStarted()

        let waitingRefresh = Task { try await waiter.forceRefreshAccessToken() }
        await store.waitUntilCoordinationRequests(2)
        #expect(await winningRefresher.callCount == 1)
        #expect(waitingRefresher.callCount == 0)

        await winningRefresher.complete()

        #expect(try await winningRefresh.value == "rotated-access")
        #expect(try await waitingRefresh.value == "rotated-access")
        #expect(await winningRefresher.callCount == 1)
        #expect(waitingRefresher.callCount == 0)
        #expect(store.saved == rotated)
        #expect(store.saveCount == 1)
        #expect(waiter.tokens == rotated)
    }

    @Test func expiryAndForcedRefreshShareOneRotation() async throws {
        let store = MemoryTokenStore(tokens(access: "expired", expiresIn: -60))
        let rotated = tokens(access: "rotated", expiresIn: 7200)
        let refresher = ControlledRefresher(next: rotated)
        let cache = AgentTokenCache(store: store, now: { now }) { tokens in
            try await refresher.run(tokens)
        }

        let first = Task { try await cache.validAccessToken() }
        await refresher.waitUntilStarted()
        #expect(await refresher.callCount == 1)
        let secondJoined = MainActorEntryBarrier()
        let second = Task { @MainActor in
            secondJoined.arrive()
            return try await cache.forceRefreshAccessToken()
        }
        await secondJoined.wait()
        #expect(await refresher.callCount == 1)
        await refresher.complete()

        #expect(try await first.value == "rotated")
        #expect(try await second.value == "rotated")
        #expect(await refresher.callCount == 1)
        #expect(store.saveCount == 1)
        #expect(store.saved == rotated)
    }

    @Test func normalReadJoinsForcedFlightAndTerminalFailureQuarantinesOldAccess() async {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let refresher = ControlledRefresher(next: tokens(access: "unused", expiresIn: 7200))
        let cache = AgentTokenCache(store: store, now: { now }) { tokens in
            try await refresher.run(tokens)
        }

        let forced = Task { try await cache.forceRefreshAccessToken() }
        await refresher.waitUntilStarted()
        let normalJoined = MainActorEntryBarrier()
        let normal = Task { @MainActor in
            normalJoined.arrive()
            return try await cache.validAccessToken()
        }
        await normalJoined.wait()
        #expect(await refresher.callCount == 1)

        let terminal = OAuthRefreshError(
            status: 400,
            code: "invalid_grant",
            reauthenticationReason: .invalidGrant
        )
        await refresher.complete(with: .failure(terminal))

        await #expect(throws: OAuthRefreshError.self) { try await forced.value }
        await #expect(throws: OAuthRefreshError.self) { try await normal.value }
        await #expect(throws: OAuthRefreshError.self) {
            try await cache.validAccessToken()
        }
        #expect(await refresher.callCount == 1)
    }

    @Test func normalReadMayUseFreshAccessAfterJoinedTransientCheckFails() async throws {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let refresher = ControlledRefresher(next: tokens(access: "unused", expiresIn: 7200))
        let cache = AgentTokenCache(store: store, now: { now }) { tokens in
            try await refresher.run(tokens)
        }

        let forced = Task { try await cache.forceRefreshAccessToken() }
        await refresher.waitUntilStarted()
        let normalJoined = MainActorEntryBarrier()
        let normal = Task { @MainActor in
            normalJoined.arrive()
            return try await cache.validAccessToken()
        }
        await normalJoined.wait()
        #expect(await refresher.callCount == 1)
        await refresher.complete(with: .failure(OAuthRefreshError(
            status: 503,
            code: "temporarily_unavailable",
            reauthenticationReason: nil
        )))

        await #expect(throws: OAuthRefreshError.self) { try await forced.value }
        #expect(try await normal.value == "fresh")
        #expect(await refresher.callCount == 1)
    }

    @Test func joinedTransientFailureCannotReturnOldAccessAfterSignOut() async throws {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let refresher = ControlledRefresher(next: tokens(access: "unused", expiresIn: 7200))
        let cache = AgentTokenCache(store: store, now: { now }) { tokens in
            try await refresher.run(tokens)
        }

        let forced = Task { try await cache.forceRefreshAccessToken() }
        await refresher.waitUntilStarted()
        let normalJoined = MainActorEntryBarrier()
        let normal = Task { @MainActor in
            normalJoined.arrive()
            return try await cache.validAccessToken()
        }
        await normalJoined.wait()
        #expect(await refresher.callCount == 1)
        try await cache.signOut()
        await refresher.complete(with: .failure(OAuthRefreshError(
            status: 503,
            code: "temporarily_unavailable",
            reauthenticationReason: nil
        )))

        await #expect(throws: (any Error).self) { try await forced.value }
        await #expect(throws: (any Error).self) { try await normal.value }
        #expect(!cache.isSignedIn)
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

    @Test func adoptingTokensPersistsThemAndSignsIn() async throws {
        let store = MemoryTokenStore(nil)
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: Refresher().run)

        try await cache.adopt(
            tokens(access: "new", expiresIn: 3600),
            ifCurrent: { true }
        )

        #expect(cache.isSignedIn)
        #expect(store.saved?.accessToken == "new")
    }

    @Test func failedLoginPersistenceDoesNotPublishTheNewAccount() async {
        let store = MemoryTokenStore(tokens(access: "old", expiresIn: 3600))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: Refresher().run)
        #expect((try? await cache.validAccessToken()) == "old")
        store.writeFailure = StoreUnavailable()

        await #expect(throws: StoreUnavailable.self) {
            try await cache.adopt(
                tokens(access: "new", expiresIn: 3600),
                ifCurrent: { true }
            )
        }

        #expect(cache.tokens?.accessToken == "old")
    }

    @Test func staleLoginCannotAdoptAfterSignOutCompletesWhileWaitingForCoordination() async throws {
        let store = OutOfOrderCoordinationStore(
            tokens(access: "old", expiresIn: 3600)
        )
        let cache = AgentTokenCache(
            store: store,
            now: { now },
            refreshTokens: Refresher().run
        )
        #expect(cache.isSignedIn)

        var loginGeneration = 1
        let attemptGeneration = loginGeneration
        let adoption = Task { @MainActor in
            try await cache.adopt(
                tokens(access: "stale-login", expiresIn: 3600),
                ifCurrent: { attemptGeneration == loginGeneration }
            )
        }
        await store.waitUntilFirstCoordinationRequest()

        // The first lease acquisition is deliberately suspended before it
        // owns the lock. This lets the later sign-out acquire, clear, and
        // publish its invalidation before the old OAuth completion resumes.
        loginGeneration += 1
        try await cache.signOut()
        #expect(!cache.isSignedIn)
        #expect(store.cleared)

        store.resumeFirstCoordinationRequest()

        await #expect(throws: UsageError.self) { try await adoption.value }
        #expect(!cache.isSignedIn)
        #expect(store.saved == nil)
        #expect(store.saveCount == 0)
    }

    @Test func aStoreThatCannotBeReadIsNotCachedAsSignedOut() async throws {
        // A locked keychain or a denied prompt is "we don't know", not "no
        // account". Latching it would sign the user out for the whole launch.
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        store.readFailure = StoreUnavailable()
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: Refresher().run)

        #expect(cache.credentialPresence == .temporarilyUnavailable)

        store.readFailure = nil

        #expect(cache.isSignedIn)
        #expect(try await cache.validAccessToken() == "fresh")
    }

    @Test func signOutDuringARefreshWinsOverTheRefreshResult() async {
        // The refresh releases the main actor for a network round trip; a
        // sign-out landing in that window must not be undone by the resumed
        // continuation writing the new tokens back.
        let store = MemoryTokenStore(tokens(access: "stale", expiresIn: -60))
        let box = CacheBox()
        let renewed = tokens(access: "renewed", expiresIn: 3600)
        let cache = AgentTokenCache(store: store, now: { now }) { _ in
            await box.signOutNow()   // the user hits Sign out mid-refresh
            return renewed
        }
        box.cache = cache

        await #expect(throws: UsageError.self) { try await cache.validAccessToken() }
        #expect(!cache.isSignedIn)
        #expect(store.saved == nil)
        #expect(store.cleared)
    }

    @Test func aFailedWriteKeepsTheRefreshedTokenForThisLaunch() async throws {
        // The provider has already rotated the old refresh token away, so
        // dropping the new pair on a keychain write failure would strand the
        // session on a credential the server no longer honours.
        let store = MemoryTokenStore(tokens(access: "stale", expiresIn: -60))
        store.writeFailure = StoreUnavailable()
        let refresher = Refresher(next: tokens(access: "renewed", expiresIn: 3600))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: refresher.run)

        await #expect(throws: RefreshedTokenPersistenceError.self) {
            try await cache.validAccessToken()
        }

        // Persisting failed, but the in-memory copy holds the live token, so the
        // rest of the launch keeps working instead of failing on every call.
        #expect(cache.tokens?.accessToken == "renewed")
        #expect(cache.hasPendingTokenPersistence)
        #expect(refresher.callCount == 1)
        #expect((try? await cache.validAccessToken()) == "renewed")
        #expect(cache.hasPendingTokenPersistence)

        store.writeFailure = nil

        #expect(try await cache.validAccessToken() == "renewed")
        #expect(!cache.hasPendingTokenPersistence)
        #expect(store.saved?.accessToken == "renewed")
        #expect(store.saveCount == 1)
        #expect(refresher.callCount == 1)
    }

    @Test func acceptedRefreshNeverReturnsAnInheritedExpiredAccessToken() async {
        let expired = tokens(access: "expired-access", expiresIn: -60, refresh: "old-refresh")
        let rotatedRefreshOnly = tokens(
            access: expired.accessToken,
            expiresIn: -60,
            refresh: "rotated-refresh"
        )
        let store = MemoryTokenStore(expired)
        let refresher = Refresher(next: rotatedRefreshOnly)
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: refresher.run)

        do {
            _ = try await cache.validAccessToken()
            Issue.record("An expired inherited bearer must never be returned")
        } catch let error as RefreshedAccessTokenUnavailableError {
            #expect(error.credentialsPersisted)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(store.saved?.refreshToken == "rotated-refresh")
        #expect(store.saved?.accessToken == "expired-access")
        #expect(cache.refreshValidationRevision == 1)
    }

    @Test func signingOutClearsTheStoreAndTheMemoryCopy() async throws {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: Refresher().run)
        _ = try await cache.validAccessToken()

        try await cache.signOut()

        #expect(!cache.isSignedIn)
        #expect(store.cleared)
    }

    @Test func failedDurableClearDoesNotPublishSignedOut() async throws {
        let store = MemoryTokenStore(tokens(access: "fresh", expiresIn: 3600))
        let cache = AgentTokenCache(store: store, now: { now }, refreshTokens: Refresher().run)
        _ = try await cache.validAccessToken()
        store.clearFailure = StoreUnavailable()

        await #expect(throws: StoreUnavailable.self) { try await cache.signOut() }

        #expect(cache.isSignedIn)
        #expect(store.saved?.accessToken == "fresh")
        #expect(!store.cleared)
    }
}

// MARK: - Fakes

/// The token store, in memory — the real one is the user's login Keychain.
private final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private(set) var saved: OAuthTokens?
    private(set) var cleared = false
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    /// When set, `load()` reports a read failure instead of an answer, and
    /// `save()` throws — the locked-keychain and denied-prompt cases.
    var readFailure: Error?
    var writeFailure: Error?
    var clearFailure: Error?

    init(_ initial: OAuthTokens?) { saved = initial }

    func save(_ tokens: OAuthTokens) throws {
        if let writeFailure { throw writeFailure }
        saveCount += 1
        saved = tokens
    }

    func load() -> Result<OAuthTokens?, Error> {
        loadCount += 1
        if let readFailure { return .failure(readFailure) }
        return .success(saved)
    }

    func clear() throws {
        if let clearFailure { throw clearFailure }
        saved = nil
        cleared = true
    }
}

/// Suspends the first coordination request before granting its lease while the
/// second request proceeds immediately. This models an OAuth adoption that has
/// entered `acquireRefreshCoordination()` but resumes only after a later
/// sign-out has completed, without relying on task timing or lock fairness.
private final class OutOfOrderCoordinationStore: TokenStore, @unchecked Sendable {
    private(set) var saved: OAuthTokens?
    private(set) var saveCount = 0
    private(set) var cleared = false
    private var coordinationRequestCount = 0
    private var firstRequestArrived = false
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?

    init(_ initial: OAuthTokens?) { saved = initial }

    func save(_ tokens: OAuthTokens) throws {
        saveCount += 1
        saved = tokens
    }

    func load() -> Result<OAuthTokens?, Error> { .success(saved) }

    func clear() throws {
        saved = nil
        cleared = true
    }

    func acquireRefreshCoordination() async throws -> any RefreshCoordinationLease {
        coordinationRequestCount += 1
        if coordinationRequestCount == 1 {
            firstRequestArrived = true
            let waiters = firstRequestWaiters
            firstRequestWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstRequestContinuation = continuation
            }
        }
        return NoOpRefreshCoordinationLease()
    }

    func waitUntilFirstCoordinationRequest() async {
        if firstRequestArrived { return }
        await withCheckedContinuation { continuation in
            firstRequestWaiters.append(continuation)
        }
    }

    func resumeFirstCoordinationRequest() {
        firstRequestContinuation?.resume()
        firstRequestContinuation = nil
    }
}

nonisolated private final class NoOpRefreshCoordinationLease: RefreshCoordinationLease {
    func release() {}
}

/// Serializes refreshes from independent caches while exposing how many have
/// reached the process-shared lease. The first cache can therefore hold the
/// lease during its network exchange while the test proves the second is
/// already queued behind it.
private final class CoordinatedTokenStore: TokenStore, @unchecked Sendable {
    private(set) var saved: OAuthTokens?
    private(set) var saveCount = 0
    private let gate = RefreshCoordinationGate()

    init(_ initial: OAuthTokens?) { saved = initial }

    func save(_ tokens: OAuthTokens) throws {
        saveCount += 1
        saved = tokens
    }

    func load() -> Result<OAuthTokens?, Error> { .success(saved) }

    func clear() throws { saved = nil }

    func acquireRefreshCoordination() async throws -> any RefreshCoordinationLease {
        await gate.acquire()
        return TestRefreshCoordinationLease(gate: gate)
    }

    func waitUntilCoordinationRequests(_ count: Int) async {
        await gate.waitUntilRequested(count)
    }
}

private actor RefreshCoordinationGate {
    private var held = false
    private var requestCount = 0
    private var leaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func acquire() async {
        requestCount += 1
        let ready = requestWaiters.filter { $0.count <= requestCount }
        requestWaiters.removeAll { $0.count <= requestCount }
        ready.forEach { $0.continuation.resume() }

        if !held {
            held = true
            return
        }
        await withCheckedContinuation { continuation in
            leaseWaiters.append(continuation)
        }
    }

    func waitUntilRequested(_ count: Int) async {
        if requestCount >= count { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func release() {
        guard !leaseWaiters.isEmpty else {
            held = false
            return
        }
        leaseWaiters.removeFirst().resume()
    }
}

nonisolated private final class TestRefreshCoordinationLease: RefreshCoordinationLease {
    private let gate: RefreshCoordinationGate

    init(gate: RefreshCoordinationGate) {
        self.gate = gate
    }

    func release() {
        Task { await gate.release() }
    }
}

private struct StoreUnavailable: Error {}
private struct UnexpectedRefresh: Error {}

/// Lets a refresh closure reach back into the cache that owns it, so a test can
/// stage a sign-out landing inside the refresh's suspension.
@MainActor
private final class CacheBox {
    var cache: AgentTokenCache?

    func signOutNow() async { try? await cache?.signOut() }
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

private actor ControlledRefresher {
    private let next: OAuthTokens
    private var continuation: CheckedContinuation<OAuthTokens, any Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0

    init(next: OAuthTokens) {
        self.next = next
    }

    func run(_: OAuthTokens) async throws -> OAuthTokens {
        callCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        if callCount > 0 { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete() {
        continuation?.resume(returning: next)
        continuation = nil
    }

    func complete(with result: Result<OAuthTokens, any Error>) {
        switch result {
        case .success(let tokens): continuation?.resume(returning: tokens)
        case .failure(let error): continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

/// `AgentTokenCache` inherits the target's MainActor default isolation. Once a
/// reader calls `arrive()`, it therefore continues into `validAccessToken()`
/// without another actor turn and can only yield after joining the existing
/// refresh flight. The waiting test cannot release that flight before then.
@MainActor
private final class MainActorEntryBarrier {
    private var arrived = false
    private var continuation: CheckedContinuation<Void, Never>?

    func arrive() {
        arrived = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        if arrived { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
