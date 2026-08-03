//
//  ConnectionStatusTests.swift
//  TokenStatsTests
//
//  The account status shown in Settings and onboarding is a join of two
//  independent axes — what the usage state says, and whether a sign-in is
//  mid-flight. It used to be computed inline against a live model, which is why
//  it went untested and grew an agent-identity check nobody caught.
//

import Testing
import Foundation

@MainActor
struct ConnectionStatusTests {

    private func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(label: "5-hour", percentConsumed: 24,
                                  resetAt: Date(timeIntervalSince1970: 1716800000))],
            fetchedAt: Date(timeIntervalSince1970: 1716700000)
        )
    }

    @Test func signedOutWithNoSignInUnderwayReadsAsSignedOut() {
        #expect(ConnectionStatus(state: .signedOut, awaitingCode: false) == .signedOut)
    }

    @Test func signedOutWhileAwaitingACodeReadsAsAwaiting() {
        #expect(ConnectionStatus(state: .signedOut, awaitingCode: true) == .awaitingCode)
    }

    @Test(arguments: [AppState.loading,
                      .fresh(.init(windows: [], fetchedAt: .init())),
                      .staleDisclosed(.init(windows: [], fetchedAt: .init()))])
    func anyNonSignedOutUsageStateReadsAsConnected(_ state: AppState) {
        #expect(ConnectionStatus(state: state, awaitingCode: false) == .connected)
    }

    @Test func usageStateWinsOverALingeringAwaitingFlag() {
        // The agent is serving data, so it is connected however the sign-in
        // flag was left. Ordering the two axes the other way would strand a
        // connected account showing "Awaiting code".
        #expect(ConnectionStatus(state: .fresh(snapshot()), awaitingCode: true) == .connected)
    }

    @Test func awaitingCodeIsPerAgentAndNeverLeaksToTheOtherAgent() {
        // The regression this join replaced: the status was derived from a
        // single app-wide flag, so it needed to name Claude Code to keep
        // "Awaiting code" off Codex. Asking per agent removes the need.
        let claude = ConnectionStatus(state: .signedOut, awaitingCode: true)
        let codex = ConnectionStatus(state: .signedOut, awaitingCode: false)

        #expect(claude == .awaitingCode)
        #expect(codex == .signedOut)
    }
}
