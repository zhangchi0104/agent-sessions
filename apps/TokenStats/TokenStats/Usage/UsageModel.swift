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
    /// Claude Code's paste-the-code flow: true while awaiting the pasted code.
    private(set) var isAwaitingCode = false

    /// User-controlled presentation preferences (order, primary, gauge style).
    let appearance: AppearanceSettings

    /// The registered Coding Agents, keyed by id. Every per-agent fact this
    /// model needs — the compact label, the provider, the auth session, the
    /// sign-in style — is read from here rather than branched on.
    private let agents: [CodingAgentID: any CodingAgentIntegration]
    private let lastKnown: LastKnownUsageStore
    private let providers: [CodingAgentID: UsageProvider]

    private var lastFetch: [CodingAgentID: Date] = [:]
    private var failures: [CodingAgentID: Int] = [:]
    private var timerTasks: [CodingAgentID: Task<Void, Never>] = [:]
    private var wakeObserver: NSObjectProtocol?

    init(appearance: AppearanceSettings,
         agents: [any CodingAgentIntegration],
         lastKnown: LastKnownUsageStore = LastKnownUsageStore()) {
        self.appearance = appearance
        self.lastKnown = lastKnown
        self.agents = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        self.providers = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.makeProvider()) })
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
        appearance.displayOrder.map { id in
            CodingAgentUsageSummary(shortLabel: agents[id]?.shortLabel ?? "?", state: agentStates[id])
        }
    }

    func isRefreshing(_ id: CodingAgentID) -> Bool { refreshing.contains(id) }

    // MARK: - Triggers

    func refreshManually(_ id: CodingAgentID) {
        Task { await refresh(id, trigger: .manual) }
    }

    func refreshAllManually() {
        for id in CodingAgentID.allCases { refreshManually(id) }
    }

    // MARK: - Auth

    /// Open the browser for one agent. A `.loopback` agent is signed in by the
    /// time this finishes; a `.pasteCode` agent then waits for the user to bring
    /// a code back to `submitPastedCode`.
    func signIn(_ id: CodingAgentID) {
        guard let agent = agents[id] else { return }
        loginError[id] = nil
        if agent.signInStyle == .pasteCode { isAwaitingCode = true }
        Task {
            do {
                try await agent.auth.beginSignIn()
                loginError[id] = nil
                if agent.signInStyle == .loopback {
                    await refresh(id, trigger: .manual)
                }
            } catch {
                loginError[id] = "Sign-in failed: \(detail(of: error))"
            }
        }
    }

    /// Finish a `.pasteCode` sign-in with the code the user brought back.
    func submitPastedCode(_ code: String, for id: CodingAgentID) {
        guard let agent = agents[id] else { return }
        Task {
            do {
                try await agent.auth.completeSignIn(pastedCode: code)
                loginError[id] = nil
                isAwaitingCode = false
                await refresh(id, trigger: .manual)
            } catch {
                loginError[id] = "Sign-in failed: \(detail(of: error))"
            }
        }
    }

    func signOut(_ id: CodingAgentID) {
        guard let agent = agents[id] else { return }
        agent.auth.signOut()
        // The pasted-code prompt belongs to whichever agent is mid-flow; signing
        // that agent out abandons it.
        if agent.signInStyle == .pasteCode { isAwaitingCode = false }
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
        agents[id]?.auth.isSignedIn ?? false
    }

    private func detail(of error: Error) -> String {
        if let usage = error as? UsageError { return usage.displayText }
        if let described = (error as? LocalizedError)?.errorDescription { return described }
        return String(describing: error)
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
