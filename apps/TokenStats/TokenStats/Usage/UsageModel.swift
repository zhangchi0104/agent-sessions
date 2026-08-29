//
//  UsageModel.swift
//  TokenStats
//
//  The coordinator: wires the pure core (RefreshPolicy, CodingAgentStateReducer)
//  to the I/O shells (providers, auth, persistence) for every Coding Agent. It
//  holds one AppState per agent (the UI renders all of them) and owns the
//  refresh triggers — per-agent timer, app-level wake, popover-open, manual.
//
//  Every agent runs the same loop, and every per-agent difference it needs
//  comes from that agent's CodingAgentIntegration rather than a branch here, so
//  one agent's failures and backoff never affect another's.
//

import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class UsageModel {
    /// One AppState per Coding Agent; the menu bar and popover derive from this.
    private(set) var agentStates = CodingAgentStates()
    /// Server-verified OAuth session state, kept separate from usage freshness
    /// so revoked credentials do not erase an honest stale snapshot.
    private(set) var sessionStates = CodingAgentSessionStates()
    /// Agents with a refresh in flight (drives per-section spinners).
    private(set) var refreshing: Set<CodingAgentID> = []
    /// Last fetch failure detail per agent, nil when the latest fetch succeeded.
    private(set) var diagnostics: [CodingAgentID: String] = [:]
    /// Sign-in failure messages per agent.
    private(set) var loginError: [CodingAgentID: String] = [:]
    /// Agents whose browser sign-in task has not finished yet. Unlike
    /// `awaitingCode`, this covers the whole self-completing flow so a second
    /// click cannot start another poll against the same subscription.
    private(set) var signingIn: Set<CodingAgentID> = []
    /// Sign-out now waits for the same cross-process credential lease as refresh
    /// and login adoption. Track it separately so duplicate clicks cannot start
    /// competing deletes while that lease is pending.
    private(set) var signingOut: Set<CodingAgentID> = []
    /// Paste-code exchanges are single-use. Track the credential generation
    /// owning each submission so Return and the Submit button cannot exchange
    /// the same code twice, and an older completion cannot unlock a newer flow.
    private var completingSignInGenerations: [CodingAgentID: Int] = [:]
    /// Agents whose sign-in has opened the browser and is now waiting for the
    /// user to bring a code back. Only a `.pasteCode` agent is ever inserted, so
    /// a reader asks whether *this* agent is waiting and never has to know which
    /// agent that is.
    private(set) var awaitingCode: Set<CodingAgentID> = []

    /// User-controlled presentation preferences (order, primary, gauge style).
    let appearance: AppearanceSettings

    private let lastKnown: LastKnownUsageStore
    /// One integration and provider per Coding Agent. Production uses the
    /// registry; UI tests inject inert integrations so even future interactions
    /// cannot touch the real Keychain or network.
    private let integrations: [CodingAgentID: any CodingAgentIntegration]
    private let providers: [CodingAgentID: UsageProvider]
    private let localizer: AppLocalizer

    private var lastFetch: [CodingAgentID: Date] = [:]
    private var failures: [CodingAgentID: Int] = [:]
    private var timerTasks: [CodingAgentID: Task<Void, Never>] = [:]
    private var sessionStateBeforeSignIn: [CodingAgentID: SessionState] = [:]
    /// Advances whenever account ownership changes. Async work from an older
    /// sign-out/sign-in generation may finish, but can no longer publish state
    /// into the replacement session.
    private var sessionGenerations: [CodingAgentID: Int] = [:]
    /// Same-generation refreshes deduplicate. A reconnect is a new generation,
    /// so it may start immediately without waiting for abandoned network work.
    private var activeRefreshGenerations: [CodingAgentID: Int] = [:]
    /// A manual check that arrives behind a non-proactive request must not be
    /// dropped: replay exactly one forced validation when that request exits.
    /// Binding it to the credential generation prevents an old request from
    /// applying the click to a replacement login.
    private var pendingManualRefreshGenerations: [CodingAgentID: Int] = [:]
    private var wakeObserver: NSObjectProtocol?

    init(appearance: AppearanceSettings,
         localizer: AppLocalizer = AppLocalizer(locale: .current),
         lastKnown: LastKnownUsageStore? = nil,
         integrations suppliedIntegrations: [any CodingAgentIntegration]? = nil) {
        let integrations = suppliedIntegrations ?? CodingAgentRegistry.all
        self.appearance = appearance
        self.localizer = localizer
        self.lastKnown = lastKnown ?? LastKnownUsageStore()
        self.integrations = Dictionary(uniqueKeysWithValues:
            integrations.map { ($0.id, $0) })
        self.providers = Dictionary(uniqueKeysWithValues:
            integrations.map { ($0.id, $0.makeProvider()) })
    }

    /// Call once on launch: restore each agent's last-known snapshot, observe
    /// wake, and kick an initial refresh per agent.
    @discardableResult
    func start() -> [CodingAgentID: Task<Void, Never>] {
        for id in CodingAgentID.allCases {
            if let snapshot = lastKnown.load(for: id) {
                // Persisted data is old by definition — show it disclosed as stale.
                apply(.fetchSucceeded(id, snapshot))
                apply(.fetchFailed(id))
            }
            switch credentialPresence(id) {
            case .present:
                sessionStates[id] = .checking
            case .absent:
                sessionStates[id] = .signedOut
                apply(.signedOut(id))
            case .temporarilyUnavailable:
                sessionStates[id] = .temporarilyUnverifiable(lastVerifiedAt: nil)
                if let persistenceWarning = retainedPersistenceDiagnostic(
                    for: id,
                    proposed: nil
                ) {
                    diagnostics[id] = persistenceWarning + "\n"
                        + credentialStoreUnavailableDiagnostic
                } else {
                    diagnostics[id] = credentialStoreUnavailableDiagnostic
                }
            }
        }
        observeWake()
        return Dictionary(uniqueKeysWithValues: CodingAgentID.allCases.map { id in
            (id, Task { await refresh(id, trigger: .startup) })
        })
    }

    // MARK: - View helpers

    /// Menu-bar readings in the user's display order (primary first).
    var menuBarSummaries: [CodingAgentUsageSummary] {
        appearance.menuBarDisplayOrder.map { id in
            CodingAgentUsageSummary(shortLabel: integration(for: id).shortLabel,
                                    state: agentStates[id])
        }
    }

    func isRefreshing(_ id: CodingAgentID) -> Bool { refreshing.contains(id) }

    func isAwaitingCode(_ id: CodingAgentID) -> Bool { awaitingCode.contains(id) }

    func isSigningIn(_ id: CodingAgentID) -> Bool { signingIn.contains(id) }

    func isSigningOut(_ id: CodingAgentID) -> Bool { signingOut.contains(id) }

    func isCompletingSignIn(_ id: CodingAgentID) -> Bool {
        completingSignInGenerations[id] != nil
    }

    // MARK: - Triggers

    @discardableResult
    func refreshManually(_ id: CodingAgentID) -> Task<Void, Never> {
        Task { await refresh(id, trigger: .manual) }
    }

    func refreshAllManually() {
        for id in CodingAgentID.allCases { refreshManually(id) }
    }

    /// Re-check all agents after the Mac wakes. Kept as one coordinator entry
    /// point so the wake path can be exercised without posting a process-wide
    /// notification in unit tests.
    func refreshAfterWake() {
        for id in CodingAgentID.allCases {
            Task { await refresh(id, trigger: .wake) }
        }
    }

    // MARK: - Auth

    /// Open the browser for one agent. A `.selfCompleting` agent is signed in by
    /// the time this finishes; a `.pasteCode` agent then waits for the user to
    /// bring a code back to `submitPastedCode`.
    func signIn(_ id: CodingAgentID) {
        guard !signingIn.contains(id),
              !signingOut.contains(id),
              completingSignInGenerations[id] == nil else { return }
        let agent = integration(for: id)
        let previousSessionState = sessionStates[id]
        let signInGeneration = advanceSessionGeneration(id)
        abandonActiveRefresh(id)
        completingSignInGenerations[id] = nil
        loginError[id] = nil
        sessionStateBeforeSignIn[id] = previousSessionState
        sessionStates[id] = .checking
        if agent.signInStyle == .pasteCode { awaitingCode.insert(id) }
        signingIn.insert(id)
        Task {
            var generation = signInGeneration
            defer {
                if isCurrentSessionGeneration(generation, for: id) {
                    signingIn.remove(id)
                }
            }
            do {
                try await agent.auth.beginSignIn(localizer: localizer)
                guard isCurrentSessionGeneration(generation, for: id) else { return }
                loginError[id] = nil
                if agent.signInStyle == .selfCompleting {
                    guard isSignedIn(id) else { return }
                    // The accepted code exchange replaced account ownership.
                    // Retire every validation that may have started against the
                    // old pair while the browser was open before publishing the
                    // new session as valid.
                    generation = advanceSessionGeneration(id)
                    abandonActiveRefresh(id)
                    signingIn.remove(id)
                    sessionStateBeforeSignIn[id] = nil
                    sessionStates[id] = .valid(verifiedAt: Date())
                    await refresh(id, trigger: .signIn)
                }
            } catch {
                guard isCurrentSessionGeneration(generation, for: id) else { return }
                // The browser never opened, so there is no code coming. Retire
                // the awaiting state with the error, or the user is left staring
                // at a paste field they can never satisfy — and cannot dismiss,
                // since Sign out only appears once connected.
                awaitingCode.remove(id)
                if case .checking = sessionStates[id] {
                    sessionStates[id] = sessionStateBeforeSignIn.removeValue(forKey: id) ?? .signedOut
                }
                diagnostics[id] = detail(of: error)
                loginError[id] = localizedSignInFailure
            }
        }
    }

    /// Finish a `.pasteCode` sign-in with the code the user brought back.
    func submitPastedCode(_ code: String, for id: CodingAgentID) {
        guard awaitingCode.contains(id),
              completingSignInGenerations[id] == nil,
              !code.isEmpty else { return }
        let generation = currentSessionGeneration(for: id)
        completingSignInGenerations[id] = generation
        Task {
            defer {
                if completingSignInGenerations[id] == generation {
                    completingSignInGenerations[id] = nil
                }
            }
            do {
                try await integration(for: id).auth.completeSignIn(
                    pastedCode: code,
                    localizer: localizer
                )
                guard isCurrentSessionGeneration(generation, for: id) else { return }
                completingSignInGenerations[id] = nil
                _ = advanceSessionGeneration(id)
                abandonActiveRefresh(id)
                loginError[id] = nil
                awaitingCode.remove(id)
                signingIn.remove(id)
                sessionStateBeforeSignIn[id] = nil
                sessionStates[id] = .valid(verifiedAt: Date())
                await refresh(id, trigger: .signIn)
            } catch {
                guard isCurrentSessionGeneration(generation, for: id) else { return }
                diagnostics[id] = detail(of: error)
                loginError[id] = localizedSignInFailure
            }
        }
    }

    func signOut(_ id: CodingAgentID) {
        guard !signingOut.contains(id) else { return }
        let previousSessionState = sessionStates[id]
        let generation = advanceSessionGeneration(id)
        abandonActiveRefresh(id)
        completingSignInGenerations[id] = nil
        // Signing an agent out abandons any code it was waiting for. An agent
        // that never waits was never in the set, so this needs no style check.
        awaitingCode.remove(id)
        signingIn.remove(id)
        signingOut.insert(id)
        sessionStateBeforeSignIn[id] = nil
        Task {
            defer {
                if isCurrentSessionGeneration(generation, for: id) {
                    signingOut.remove(id)
                }
            }
            do {
                try await integration(for: id).auth.signOut()
            } catch {
                guard isCurrentSessionGeneration(generation, for: id) else { return }
                // Do not claim durable sign-out or erase history when secure-store
                // deletion failed; the old credential could otherwise reappear on
                // the next launch. The concrete error is intentionally hidden.
                switch previousSessionState {
                case .signedOut, .checking:
                    sessionStates[id] = .temporarilyUnverifiable(lastVerifiedAt: nil)
                case .valid, .reauthenticationRequired, .temporarilyUnverifiable:
                    sessionStates[id] = previousSessionState
                }
                diagnostics[id] = credentialStoreUnavailableDiagnostic
                loginError[id] = localizedSignOutFailure
                failures[id] = (failures[id] ?? 0) + 1
                apply(.fetchFailed(id))
                scheduleNextTimerUnlessQuarantined(id)
                return
            }
            guard isCurrentSessionGeneration(generation, for: id) else { return }
            sessionStates[id] = .signedOut
            lastKnown.clear(for: id)
            lastFetch[id] = nil
            failures[id] = 0
            diagnostics[id] = nil
            loginError[id] = nil
            apply(.signedOut(id))
        }
    }

    func quit() { NSApplication.shared.terminate(nil) }

    // MARK: - Core loop (per agent)

    private func refresh(_ id: CodingAgentID, trigger: RefreshTrigger) async {
        let generation = currentSessionGeneration(for: id)
        // A reconnect deliberately retains the old credential until the new
        // code exchange succeeds. Never validate or fetch with that old pair
        // while browser/code completion is still in progress; the successful
        // exchange and ensuing SignIn fetch satisfy any intervening trigger.
        if signingIn.contains(id) || signingOut.contains(id) || awaitingCode.contains(id) {
            scheduleNextTimerUnlessQuarantined(id)
            return
        }
        // A fetch is already in flight for this agent; let it finish (and
        // reschedule the timer) rather than firing a duplicate network call.
        guard activeRefreshGenerations[id] != generation else {
            if case .manual = trigger {
                switch sessionStates[id] {
                case .signedOut, .reauthenticationRequired:
                    // Terminal sessions stay quarantined until reconnect/sign out.
                    break
                case .checking, .valid, .temporarilyUnverifiable:
                    pendingManualRefreshGenerations[id] = generation
                }
            }
            return
        }
        // A terminally rejected token pair stays quarantined in the Keychain
        // until explicit Sign out or a successful reconnect, but must never be
        // sent again automatically.
        if case .reauthenticationRequired = sessionStates[id] { return }
        let decision = RefreshPolicy.decide(
            trigger: trigger, lastFetch: lastFetch[id], now: Date(),
            consecutiveFailures: failures[id] ?? 0
        )
        guard decision.shouldFetch else {
            scheduleTimer(id, after: decision.nextInterval)
            return
        }
        let auth = integration(for: id).auth
        switch auth.credentialPresence {
        case .present:
            break
        case .absent:
            sessionStates[id] = .signedOut
            apply(.signedOut(id))
            // Keep the loop alive. A signed-out reading can be transient — a
            // keychain that wasn't readable yet — and without a timer here that
            // agent would never poll again for the rest of the launch.
            scheduleTimer(id, after: decision.nextInterval)
            return
        case .temporarilyUnavailable:
            let lastVerifiedAt = sessionStates[id].lastVerifiedAt
            sessionStates[id] = .temporarilyUnverifiable(lastVerifiedAt: lastVerifiedAt)
            recordFailure(id, error: CredentialStoreUnavailableError())
            scheduleNextTimerUnlessQuarantined(id)
            return
        }
        guard let provider = providers[id] else { return }

        apply(.loadingStarted(id))
        activeRefreshGenerations[id] = generation
        refreshing.insert(id)
        defer {
            var replayManual = false
            if pendingManualRefreshGenerations[id] == generation {
                pendingManualRefreshGenerations[id] = nil
                switch trigger {
                case .startup, .manual:
                    // The in-flight request already performed the requested
                    // proactive validation, so its result is the shared result.
                    break
                case .timer, .wake, .popoverOpen, .signIn:
                    replayManual = true
                }
            }
            if activeRefreshGenerations[id] == generation {
                activeRefreshGenerations[id] = nil
                refreshing.remove(id)
            }
            if replayManual,
               isCurrentSignedInSession(generation, for: id) {
                Task { await refresh(id, trigger: .manual) }
            }
        }

        var proactivelyValidated = false
        var successfulValidationDiagnostic: String?
        if auth.supportsProactiveSessionValidation, trigger.requiresProactiveSessionValidation {
            let lastVerifiedAt = sessionStates[id].lastVerifiedAt
            sessionStates[id] = .checking
            do {
                _ = try await auth.forceRefreshAccessToken()
                guard isCurrentSignedInSession(generation, for: id) else { return }
                sessionStates[id] = .valid(verifiedAt: Date())
                proactivelyValidated = true
            } catch let error as RefreshedAccessTokenUnavailableError {
                guard isCurrentSignedInSession(generation, for: id) else { return }
                // The refresh grant itself was accepted, so the session is
                // valid. Do not send the inherited expired access token; keep
                // usage stale and let the next timer retry with the rotated
                // refresh token already adopted by the cache.
                sessionStates[id] = .valid(verifiedAt: Date())
                recordFailure(id, error: error)
                scheduleNextTimerUnlessQuarantined(id)
                return
            } catch is RefreshedTokenPersistenceError {
                guard isCurrentSignedInSession(generation, for: id) else { return }
                // The server accepted the refresh and the live pair remains in
                // memory. Continue this launch while surfacing the durable-store
                // warning without exposing the underlying Keychain response.
                sessionStates[id] = .valid(verifiedAt: Date())
                proactivelyValidated = true
                successfulValidationDiagnostic = refreshedCredentialPersistenceDiagnostic
            } catch {
                // A user sign-out during refresh owns the final state.
                guard isCurrentSignedInSession(generation, for: id) else { return }
                if let reason = reauthenticationReason(of: error) {
                    requireReauthentication(id, reason: reason, error: error)
                } else {
                    sessionStates[id] = .temporarilyUnverifiable(lastVerifiedAt: lastVerifiedAt)
                    recordFailure(id, error: error)
                }
                scheduleNextTimerUnlessQuarantined(id)
                return
            }
        }

        await fetchUsage(
            id,
            provider: provider,
            alreadyForceRefreshed: proactivelyValidated,
            generation: generation,
            successfulValidationDiagnostic: successfulValidationDiagnostic
        )
        guard isCurrentSessionGeneration(generation, for: id) else { return }
        scheduleNextTimerUnlessQuarantined(id)
    }

    private func fetchUsage(
        _ id: CodingAgentID,
        provider: UsageProvider,
        alreadyForceRefreshed: Bool,
        generation: Int,
        successfulValidationDiagnostic: String?
    ) async {
        let auth = integration(for: id).auth
        let refreshRevisionBeforeFetch = auth.refreshValidationRevision
        let lastVerifiedAtBeforeFetch = sessionStates[id].lastVerifiedAt
        do {
            let reading = try await provider.fetchUsage()
            guard isCurrentSignedInSession(generation, for: id) else { return }
            recordNaturalRefreshValidation(
                id,
                auth: auth,
                revisionBeforeFetch: refreshRevisionBeforeFetch
            )
            commit(
                reading,
                for: id,
                usageVerifiesSession: !integration(for: id).auth.supportsProactiveSessionValidation,
                successfulValidationDiagnostic: successfulValidationDiagnostic
            )
        } catch let error as RefreshedAccessTokenUnavailableError {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            sessionStates[id] = .valid(verifiedAt: Date())
            recordFailure(id, error: error)
        } catch is RefreshedTokenPersistenceError {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            // An expiry refresh can happen inside the provider's access-token
            // closure. The rotation succeeded even though storage did not, so
            // retry the usage call once with the in-memory token.
            sessionStates[id] = .valid(verifiedAt: Date())
            await fetchAfterSuccessfulValidation(
                id,
                provider: provider,
                generation: generation,
                successfulValidationDiagnostic: refreshedCredentialPersistenceDiagnostic
            )
        } catch let error as OAuthRefreshError {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            if let reason = error.reauthenticationReason {
                requireReauthentication(id, reason: reason, error: error)
            } else {
                // This error came from access-token acquisition inside the
                // provider, not from the Usage endpoint. A natural refresh that
                // could not be verified downgrades session confidence even if
                // the previously verified access token had been valid.
                sessionStates[id] = .temporarilyUnverifiable(
                    lastVerifiedAt: lastVerifiedAtBeforeFetch
                )
                recordFailure(id, error: error)
            }
        } catch let error as UsageError {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            recordNaturalRefreshValidation(
                id,
                auth: auth,
                revisionBeforeFetch: refreshRevisionBeforeFetch
            )
            if case .unauthorized = error {
                if !integration(for: id).auth.supportsProactiveSessionValidation {
                    markOrdinaryFailure(id, error: error)
                } else if alreadyForceRefreshed {
                    requireReauthentication(id, reason: .unauthorized, error: error)
                } else {
                    await recoverUnauthorized(id, provider: provider, generation: generation)
                }
            } else {
                markOrdinaryFailure(
                    id,
                    error: error,
                    preserving: successfulValidationDiagnostic
                )
            }
        } catch {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            recordNaturalRefreshValidation(
                id,
                auth: auth,
                revisionBeforeFetch: refreshRevisionBeforeFetch
            )
            if let reason = reauthenticationReason(of: error) {
                requireReauthentication(id, reason: reason, error: error)
            } else {
                markOrdinaryFailure(
                    id,
                    error: error,
                    preserving: successfulValidationDiagnostic
                )
            }
        }
    }

    /// A timer/wake request can refresh naturally inside the provider's token
    /// closure. That accepted refresh is authoritative session proof even
    /// though Codex Usage success alone is not.
    private func recordNaturalRefreshValidation(
        _ id: CodingAgentID,
        auth: any AgentAuthSession,
        revisionBeforeFetch: Int
    ) {
        guard auth.supportsProactiveSessionValidation,
              auth.refreshValidationRevision != revisionBeforeFetch else { return }
        sessionStates[id] = .valid(verifiedAt: Date())
    }

    private func recoverUnauthorized(
        _ id: CodingAgentID,
        provider: UsageProvider,
        generation: Int
    ) async {
        let auth = integration(for: id).auth
        let lastVerifiedAt = sessionStates[id].lastVerifiedAt
        sessionStates[id] = .checking

        do {
            _ = try await auth.forceRefreshAccessToken()
            guard isCurrentSignedInSession(generation, for: id) else { return }
            sessionStates[id] = .valid(verifiedAt: Date())
        } catch let error as RefreshedAccessTokenUnavailableError {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            sessionStates[id] = .valid(verifiedAt: Date())
            recordFailure(id, error: error)
            return
        } catch is RefreshedTokenPersistenceError {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            sessionStates[id] = .valid(verifiedAt: Date())
            await fetchAfterSuccessfulValidation(
                id,
                provider: provider,
                generation: generation,
                successfulValidationDiagnostic: refreshedCredentialPersistenceDiagnostic
            )
            return
        } catch {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            if let reason = reauthenticationReason(of: error) {
                requireReauthentication(id, reason: reason, error: error)
            } else {
                sessionStates[id] = .temporarilyUnverifiable(lastVerifiedAt: lastVerifiedAt)
                recordFailure(id, error: error)
            }
            return
        }

        await fetchAfterSuccessfulValidation(
            id,
            provider: provider,
            generation: generation,
            successfulValidationDiagnostic: nil
        )
    }

    private func fetchAfterSuccessfulValidation(
        _ id: CodingAgentID,
        provider: UsageProvider,
        generation: Int,
        successfulValidationDiagnostic: String?
    ) async {
        do {
            let reading = try await provider.fetchUsage()
            guard isCurrentSignedInSession(generation, for: id) else { return }
            commit(
                reading,
                for: id,
                usageVerifiesSession: false,
                successfulValidationDiagnostic: successfulValidationDiagnostic
            )
        } catch let retryError as UsageError {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            if case .unauthorized = retryError,
               integration(for: id).auth.supportsProactiveSessionValidation {
                requireReauthentication(id, reason: .unauthorized, error: retryError)
            } else {
                // The successful refresh already proved the session. A 403,
                // rate limit, server error, or parse failure only stales usage.
                recordFailure(
                    id,
                    error: retryError,
                    preserving: successfulValidationDiagnostic
                )
            }
        } catch {
            guard isCurrentSignedInSession(generation, for: id) else { return }
            recordFailure(
                id,
                error: error,
                preserving: successfulValidationDiagnostic
            )
        }
    }

    private func commit(
        _ reading: UsageReading,
        for id: CodingAgentID,
        usageVerifiesSession: Bool,
        successfulValidationDiagnostic: String?
    ) {
        let now = Date()
        let snapshot = UsageSnapshot(windows: reading.windows, fetchedAt: now)
        lastKnown.save(snapshot, for: id)
        lastFetch[id] = now
        failures[id] = 0
        if let retainedDiagnostic = retainedPersistenceDiagnostic(
            for: id,
            proposed: successfulValidationDiagnostic
        ) {
            diagnostics[id] = retainedDiagnostic
        } else if !usageVerifiesSession,
                  case .temporarilyUnverifiable = sessionStates[id] {
            // A normal Codex usage 200 does not resolve the earlier inability
            // to validate its refresh grant, so retain that validation detail.
        } else {
            diagnostics[id] = nil
        }
        // Codex usage success proves only that the current access token works;
        // it cannot upgrade a refresh-token session whose force validation was
        // temporarily unverifiable. Non-proactive integrations still use a
        // successful usage response as their session proof.
        if usageVerifiesSession {
            sessionStates[id] = .valid(verifiedAt: now)
        }
        apply(.fetchSucceeded(id, snapshot))
    }

    private func markOrdinaryFailure(
        _ id: CodingAgentID,
        error: Error,
        preserving successfulValidationDiagnostic: String? = nil
    ) {
        if case .checking = sessionStates[id] {
            sessionStates[id] = .temporarilyUnverifiable(lastVerifiedAt: nil)
        }
        recordFailure(
            id,
            error: error,
            preserving: successfulValidationDiagnostic
        )
    }

    private func requireReauthentication(
        _ id: CodingAgentID,
        reason: SessionReauthenticationReason,
        error: Error
    ) {
        sessionStates[id] = .reauthenticationRequired(reason: reason)
        recordFailure(id, error: error)
    }

    private func recordFailure(
        _ id: CodingAgentID,
        error: Error,
        preserving successfulValidationDiagnostic: String? = nil
    ) {
        let failure = detail(of: error)
        if let retainedDiagnostic = retainedPersistenceDiagnostic(
            for: id,
            proposed: successfulValidationDiagnostic
        ),
           !retainedDiagnostic.isEmpty,
           retainedDiagnostic != failure {
            diagnostics[id] = retainedDiagnostic + "\n" + failure
        } else {
            diagnostics[id] = failure
        }
        failures[id] = (failures[id] ?? 0) + 1
        apply(.fetchFailed(id))
    }

    /// A persistence warning is state, not merely the detail attached to one
    /// failed fetch. Retain it while the cache still owns an undurable pair and
    /// discard a stale proposed warning immediately after a retry succeeds.
    private func retainedPersistenceDiagnostic(
        for id: CodingAgentID,
        proposed: String?
    ) -> String? {
        if integration(for: id).auth.hasPendingTokenPersistence {
            return refreshedCredentialPersistenceDiagnostic
        }
        if proposed == refreshedCredentialPersistenceDiagnostic { return nil }
        return proposed
    }

    private func scheduleNextTimerUnlessQuarantined(_ id: CodingAgentID) {
        guard !sessionStates[id].isSignedOut else { return }
        if case .reauthenticationRequired = sessionStates[id] { return }
        scheduleTimer(id, after: RefreshPolicy.decide(
            trigger: .timer, lastFetch: lastFetch[id], now: Date(),
            consecutiveFailures: failures[id] ?? 0
        ).nextInterval)
    }

    private func reauthenticationReason(of error: Error) -> SessionReauthenticationReason? {
        (error as? OAuthRefreshError)?.reauthenticationReason
    }

    private func apply(_ event: CodingAgentEvent) {
        agentStates = CodingAgentStateReducer.reduce(state: agentStates, event: event)
    }

    private func isSignedIn(_ id: CodingAgentID) -> Bool {
        integration(for: id).auth.isSignedIn
    }

    private func credentialPresence(_ id: CodingAgentID) -> CredentialPresence {
        integration(for: id).auth.credentialPresence
    }

    private func currentSessionGeneration(for id: CodingAgentID) -> Int {
        sessionGenerations[id, default: 0]
    }

    @discardableResult
    private func advanceSessionGeneration(_ id: CodingAgentID) -> Int {
        let generation = currentSessionGeneration(for: id) + 1
        sessionGenerations[id] = generation
        pendingManualRefreshGenerations[id] = nil
        return generation
    }

    private func isCurrentSessionGeneration(_ generation: Int, for id: CodingAgentID) -> Bool {
        currentSessionGeneration(for: id) == generation
    }

    private func isCurrentSignedInSession(_ generation: Int, for id: CodingAgentID) -> Bool {
        guard isCurrentSessionGeneration(generation, for: id) else { return false }
        guard isSignedIn(id) else {
            // The account may have been removed by another app instance while
            // this one waited for the credential lease. Converge presentation
            // and history instead of leaving the section stuck in `checking`.
            sessionStates[id] = .signedOut
            lastKnown.clear(for: id)
            lastFetch[id] = nil
            failures[id] = 0
            diagnostics[id] = nil
            loginError[id] = nil
            apply(.signedOut(id))
            scheduleTimer(id, after: RefreshPolicy.baseInterval)
            return false
        }
        return true
    }

    private func abandonActiveRefresh(_ id: CodingAgentID) {
        activeRefreshGenerations[id] = nil
        refreshing.remove(id)
    }

    private func integration(for id: CodingAgentID) -> any CodingAgentIntegration {
        guard let integration = integrations[id] else {
            preconditionFailure("No CodingAgentIntegration supplied for \(id.rawValue)")
        }
        return integration
    }

    private func detail(of error: Error) -> String {
        if let usage = error as? UsageError { return usage.displayText(using: localizer) }
        if let refresh = error as? OAuthRefreshError {
            return UsageError.badResponse(
                status: refresh.status,
                body: refresh.diagnosticSummary
            ).displayText(using: localizer)
        }
        if error is RefreshedTokenPersistenceError {
            return refreshedCredentialPersistenceDiagnostic
        }
        if let unavailable = error as? RefreshedAccessTokenUnavailableError {
            if unavailable.credentialsPersisted {
                return refreshedAccessTokenUnavailableDiagnostic
            }
            return refreshedAccessTokenUnavailableDiagnostic
                + "\n" + refreshedCredentialPersistenceDiagnostic
        }
        if error is CredentialStoreUnavailableError {
            return credentialStoreUnavailableDiagnostic
        }
        if let listener = error as? LoopbackAuthListener.ListenerError {
            return listener.localizedDescription(using: localizer)
        }
        if let described = (error as? LocalizedError)?.errorDescription { return described }
        return String(describing: error)
    }

    private var refreshedCredentialPersistenceDiagnostic: String {
        localizer.localized(
            LocalizedStringResource.usageSessionCredentialsPersistenceWarning
        )
    }

    private var credentialStoreUnavailableDiagnostic: String {
        localizer.localized(
            LocalizedStringResource.usageSessionCredentialsUnavailable
        )
    }

    private var refreshedAccessTokenUnavailableDiagnostic: String {
        localizer.localized(
            LocalizedStringResource.usageSessionRefreshedAccessUnavailable
        )
    }

    private var localizedSignInFailure: String {
        localizer.localized(
            LocalizedStringResource.accountSignInFailedSummary
        )
    }

    private var localizedSignOutFailure: String {
        localizer.localized(
            LocalizedStringResource.accountSignOutFailedSummary
        )
    }

    // MARK: - Timer & wake

    private func scheduleTimer(_ id: CodingAgentID, after interval: TimeInterval) {
        timerTasks[id]?.cancel()
        timerTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await self?.refresh(id, trigger: .timer)
        }
    }

    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAfterWake()
            }
        }
    }
}
