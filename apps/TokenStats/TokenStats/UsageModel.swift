//
//  UsageModel.swift
//  TokenStats
//
//  The coordinator: wires the pure core (RefreshPolicy, CodingAgentStateReducer)
//  to the I/O shells (providers, auth, persistence) for every Coding Agent. It
//  holds one AppState per agent (the UI renders all of them) and owns the
//  refresh triggers — per-agent timer, app-level wake, popover-open, manual.
//
//  Each agent runs the same loop the single-agent model used, parameterized by
//  CodingAgentID, so one agent's failures/backoff never affect another's.
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

    /// Compact menu-bar labels (PRD). Display *order* is now user-controlled
    /// via `appearance`; internal refresh loops iterate `CodingAgentID.allCases`.
    static let shortLabels: [CodingAgentID: String] = [.claudeCode: "C", .codex: "X"]

    /// User-controlled presentation preferences (order, primary, gauge style).
    let appearance: AppearanceSettings

    private let claudeAuth: AuthSession
    private let codexAuth: CodexAuthSession
    private let lastKnown: LastKnownUsageStore
    private let providers: [CodingAgentID: UsageProvider]

    private var lastFetch: [CodingAgentID: Date] = [:]
    private var failures: [CodingAgentID: Int] = [:]
    private var timerTasks: [CodingAgentID: Task<Void, Never>] = [:]
    private var wakeObserver: NSObjectProtocol?

    init(appearance: AppearanceSettings,
         claudeAuth: AuthSession = AuthSession(),
         codexAuth: CodexAuthSession = CodexAuthSession(),
         lastKnown: LastKnownUsageStore = LastKnownUsageStore()) {
        self.appearance = appearance
        self.claudeAuth = claudeAuth
        self.codexAuth = codexAuth
        self.lastKnown = lastKnown
        self.providers = [
            .claudeCode: ClaudeCodeUsageProvider(accessToken: { [claudeAuth] in
                try await claudeAuth.validAccessToken()
            }),
            .codex: CodexUsageProvider(
                accessToken: { [codexAuth] in try await codexAuth.validAccessToken() },
                accountID: { [codexAuth] in codexAuth.accountID() }
            ),
        ]
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
            CodingAgentUsageSummary(shortLabel: Self.shortLabels[id] ?? "?", state: agentStates[id])
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

    /// Claude Code: open the browser; the user pastes a code back.
    func signInClaude() {
        loginError[.claudeCode] = nil
        isAwaitingCode = true
        claudeAuth.beginLogin()
    }

    func submitPastedCode(_ code: String) {
        Task {
            do {
                try await claudeAuth.completeLogin(pastedCode: code)
                loginError[.claudeCode] = nil
                isAwaitingCode = false
                await refresh(.claudeCode, trigger: .manual)
            } catch {
                loginError[.claudeCode] = "Sign-in failed: \(detail(of: error))"
            }
        }
    }

    /// Codex: one-shot loopback login (browser approval, no paste).
    func signInCodex() {
        loginError[.codex] = nil
        Task {
            do {
                try await codexAuth.login()
                loginError[.codex] = nil
                await refresh(.codex, trigger: .manual)
            } catch {
                loginError[.codex] = "Sign-in failed: \(detail(of: error))"
            }
        }
    }

    func signOut(_ id: CodingAgentID) {
        switch id {
        case .claudeCode:
            claudeAuth.signOut()
            isAwaitingCode = false
        case .codex:
            codexAuth.signOut()
        }
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
            let snapshot = UsageSnapshot(windows: reading.windows, credits: reading.credits, fetchedAt: Date())
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
        switch id {
        case .claudeCode: return claudeAuth.isSignedIn
        case .codex: return codexAuth.isSignedIn
        }
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
