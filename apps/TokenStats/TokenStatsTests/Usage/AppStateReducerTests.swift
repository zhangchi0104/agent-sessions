//
//  AppStateReducerTests.swift
//  TokenStatsTests
//

import Testing
import Foundation

struct AppStateReducerTests {

    private func snapshot(percent: Double = 42) -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(label: "5-hour", percentConsumed: percent,
                                  resetAt: Date(timeIntervalSince1970: 1716800000))],
            fetchedAt: Date(timeIntervalSince1970: 1716700000)
        )
    }

    @Test func successfulFetchBecomesFresh() {
        let snap = snapshot()
        let state = AppStateReducer.reduce(state: .loading, event: .fetchSucceeded(snap))

        #expect(state == .fresh(snap))
    }

    @Test func failureWithLastKnownBecomesStaleDisclosed() {
        let snap = snapshot()
        let state = AppStateReducer.reduce(state: .fresh(snap), event: .fetchFailed)

        // Must keep showing the last-known snapshot, marked stale — never blank.
        #expect(state == .staleDisclosed(snap))
    }

    @Test func failureWhileAlreadyStaleKeepsTheSnapshot() {
        let snap = snapshot()
        let state = AppStateReducer.reduce(state: .staleDisclosed(snap), event: .fetchFailed)

        #expect(state == .staleDisclosed(snap))
    }

    @Test(arguments: [AppState.fresh(.init(windows: [], fetchedAt: .init())),
                      .staleDisclosed(.init(windows: [], fetchedAt: .init())),
                      .loading])
    func signOutEventAlwaysGoesToSignedOut(from start: AppState) {
        let state = AppStateReducer.reduce(state: start, event: .signedOut)

        #expect(state == .signedOut)
    }

    @Test func loadingStartedFromSignedOutBecomesLoading() {
        let state = AppStateReducer.reduce(state: .signedOut, event: .loadingStarted)

        #expect(state == .loading)
    }

    @Test func loadingStartedKeepsExistingSnapshotVisible() {
        let snap = snapshot()
        // Refreshing while we already show data must not blank the display.
        let state = AppStateReducer.reduce(state: .fresh(snap), event: .loadingStarted)

        #expect(state == .fresh(snap))
    }

    @Test func targetedFetchSuccessUpdatesOnlyThatCodingAgent() {
        let claudeSnapshot = snapshot(percent: 24)
        let codexSnapshot = snapshot(percent: 12)
        let start = CodingAgentStates([
            .claudeCode: .loading,
            .codex: .fresh(codexSnapshot),
        ])

        let state = CodingAgentStateReducer.reduce(
            state: start,
            event: .fetchSucceeded(.claudeCode, claudeSnapshot)
        )

        #expect(state[.claudeCode] == .fresh(claudeSnapshot))
        #expect(state[.codex] == .fresh(codexSnapshot))
    }

    @Test func targetedFetchFailureStalesOnlyThatCodingAgent() {
        let claudeSnapshot = snapshot(percent: 24)
        let codexSnapshot = snapshot(percent: 12)
        let start = CodingAgentStates([
            .claudeCode: .fresh(claudeSnapshot),
            .codex: .fresh(codexSnapshot),
        ])

        let state = CodingAgentStateReducer.reduce(
            state: start,
            event: .fetchFailed(.claudeCode)
        )

        #expect(state[.claudeCode] == .staleDisclosed(claudeSnapshot))
        #expect(state[.codex] == .fresh(codexSnapshot))
    }
}
