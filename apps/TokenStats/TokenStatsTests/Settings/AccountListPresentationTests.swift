//
//  AccountListPresentationTests.swift
//  TokenStatsTests
//

import Foundation
import Testing
@testable import TokenStats

struct AccountListPresentationTests {
    private let displayOrder: [CodingAgentID] = [.claudeCode, .codex]

    @Test func signedOutAccountsAreAvailableInsteadOfDisplayed() {
        let states = CodingAgentStates()

        #expect(
            AccountListPresentation.displayedAccounts(
                in: displayOrder,
                states: states,
                pending: []
            ).isEmpty
        )
        #expect(
            AccountListPresentation.availableAccounts(
                in: displayOrder,
                states: states,
                pending: []
            ) == displayOrder
        )
    }

    @Test func connectedAndPendingAccountsCannotBeAddedAgain() {
        var states = CodingAgentStates()
        states[.claudeCode] = .loading

        #expect(
            AccountListPresentation.displayedAccounts(
                in: displayOrder,
                states: states,
                pending: [.codex]
            ) == displayOrder
        )
        #expect(
            AccountListPresentation.availableAccounts(
                in: displayOrder,
                states: states,
                pending: [.codex]
            ).isEmpty
        )
    }

    @Test func accountRowsKeepTheUsersDisplayOrder() {
        var states = CodingAgentStates()
        states[.claudeCode] = .loading

        #expect(
            AccountListPresentation.displayedAccounts(
                in: [.codex, .claudeCode],
                states: states,
                pending: [.codex]
            ) == [.codex, .claudeCode]
        )
    }
}
