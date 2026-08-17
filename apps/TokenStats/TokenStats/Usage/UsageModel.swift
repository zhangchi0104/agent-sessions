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
    func start() {
        for id in CodingAgentID.allCases {
            if let snapshot = lastKnown.load(for: id) {
                // Persisted data is old by definition — show it disclosed as stale.
                apply(.fetchSucceeded(id, snapshot))
                apply(.fetchFailed(id))
            }
            if !isSignedIn(id) {
                apply(.signedOut(id))
            }
        }
        observeWake()
        for id in CodingAgentID.allCases {
            Task { await refresh(id, trigger: .timer) }
        }
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

    // MARK: - Triggers

    func refreshManually(_ id: CodingAgentID) {
        Task { await refresh(id, trigger: .manual) }
    }

    func refreshAllManually() {
        for id in CodingAgentID.allCases { refreshManually(id) }
    }

    // MARK: - Auth

    /// Open the browser for one agent. A `.selfCompleting` agent is signed in by
    /// the time this finishes; a `.pasteCode` agent then waits for the user to
    /// bring a code back to `submitPastedCode`.
    func signIn(_ id: CodingAgentID) {
        guard !signingIn.contains(id) else { return }
        let agent = integration(for: id)
        loginError[id] = nil
        if agent.signInStyle == .pasteCode { awaitingCode.insert(id) }
        signingIn.insert(id)
        Task {
            defer { signingIn.remove(id) }
            do {
                try await agent.auth.beginSignIn(localizer: localizer)
                loginError[id] = nil
                if agent.signInStyle == .selfCompleting {
                    await refresh(id, trigger: .manual)
                }
            } catch {
                // The browser never opened, so there is no code coming. Retire
                // the awaiting state with the error, or the user is left staring
                // at a paste field they can never satisfy — and cannot dismiss,
                // since Sign out only appears once connected.
                awaitingCode.remove(id)
                diagnostics[id] = detail(of: error)
                loginError[id] = localizedSignInFailure
            }
        }
    }

    /// Finish a `.pasteCode` sign-in with the code the user brought back.
    func submitPastedCode(_ code: String, for id: CodingAgentID) {
        Task {
            do {
                try await integration(for: id).auth.completeSignIn(
                    pastedCode: code,
                    localizer: localizer
                )
                loginError[id] = nil
                awaitingCode.remove(id)
                await refresh(id, trigger: .manual)
            } catch {
                diagnostics[id] = detail(of: error)
                loginError[id] = localizedSignInFailure
            }
        }
    }

    func signOut(_ id: CodingAgentID) {
        integration(for: id).auth.signOut()
        // Signing an agent out abandons any code it was waiting for. An agent
        // that never waits was never in the set, so this needs no style check.
        awaitingCode.remove(id)
        lastKnown.clear(for: id)
        lastFetch[id] = nil
        failures[id] = 0
        diagnostics[id] = nil
        apply(.signedOut(id))
    }

    func quit() { NSApplication.shared.terminate(nil) }

    // MARK: - Core loop (per agent)

    private func refresh(_ id: CodingAgentID, trigger: RefreshTrigger) async {
        // A fetch is already in flight for this agent; let it finish (and
        // reschedule the timer) rather than firing a duplicate network call.
        guard !refreshing.contains(id) else { return }
        let decision = RefreshPolicy.decide(
            trigger: trigger, lastFetch: lastFetch[id], now: Date(),
            consecutiveFailures: failures[id] ?? 0
        )
        guard decision.shouldFetch else {
            scheduleTimer(id, after: decision.nextInterval)
            return
        }
        guard isSignedIn(id) else {
            apply(.signedOut(id))
            // Keep the loop alive. A signed-out reading can be transient — a
            // keychain that wasn't readable yet — and without a timer here that
            // agent would never poll again for the rest of the launch.
            scheduleTimer(id, after: decision.nextInterval)
            return
        }
        guard let provider = providers[id] else { return }

        apply(.loadingStarted(id))
        refreshing.insert(id)
        defer { refreshing.remove(id) }

        do {
            let reading = try await provider.fetchUsage()
            // The user may have signed out while the fetch was in flight; if so,
            // discard the result rather than resurrecting cleared usage.
            guard isSignedIn(id) else { return }
            let snapshot = UsageSnapshot(windows: reading.windows, fetchedAt: Date())
            lastKnown.save(snapshot, for: id)
            lastFetch[id] = Date()
            failures[id] = 0
            diagnostics[id] = nil
            apply(.fetchSucceeded(id, snapshot))
        } catch {
            // Same reasoning as the success path: a sign-out during the fetch
            // has already cleared this agent's diagnostics and failure count,
            // and writing the failure back would re-arm a backoff timer for an
            // account the user just disconnected.
            guard isSignedIn(id) else { return }
            diagnostics[id] = detail(of: error)
            failures[id] = (failures[id] ?? 0) + 1
            apply(.fetchFailed(id))
        }

        scheduleTimer(id, after: RefreshPolicy.decide(
            trigger: .timer, lastFetch: lastFetch[id], now: Date(),
            consecutiveFailures: failures[id] ?? 0
        ).nextInterval)
    }

    private func apply(_ event: CodingAgentEvent) {
        agentStates = CodingAgentStateReducer.reduce(state: agentStates, event: event)
    }

    private func isSignedIn(_ id: CodingAgentID) -> Bool {
        integration(for: id).auth.isSignedIn
    }

    private func integration(for id: CodingAgentID) -> any CodingAgentIntegration {
        guard let integration = integrations[id] else {
            preconditionFailure("No CodingAgentIntegration supplied for \(id.rawValue)")
        }
        return integration
    }

    private func detail(of error: Error) -> String {
        if let usage = error as? UsageError { return usage.displayText(using: localizer) }
        if let listener = error as? LoopbackAuthListener.ListenerError {
            return listener.localizedDescription(using: localizer)
        }
        if let described = (error as? LocalizedError)?.errorDescription { return described }
        return String(describing: error)
    }

    private var localizedSignInFailure: String {
        localizer.localized(
            LocalizedStringResource.accountSignInFailedSummary
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
                guard let self else { return }
                for id in CodingAgentID.allCases { Task { await self.refresh(id, trigger: .wake) } }
            }
        }
    }
}
