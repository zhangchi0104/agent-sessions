//
//  SubscriptionListPresentationTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

struct SubscriptionListPresentationTests {
    private let displayOrder: [CodingAgentID] = [.claudeCode, .codex]

    @Test func signedOutSubscriptionsAreAvailableInsteadOfDisplayed() {
        let states = CodingAgentStates()

        #expect(
            SubscriptionListPresentation.displayedSubscriptions(
                in: displayOrder,
                states: states,
                pending: []
            ).isEmpty
        )
        #expect(
            SubscriptionListPresentation.availableSubscriptions(
                in: displayOrder,
                states: states,
                pending: []
            ) == displayOrder
        )
    }

    @Test func connectedAndPendingSubscriptionsCannotBeAddedAgain() {
        var states = CodingAgentStates()
        states[.claudeCode] = .loading

        #expect(
            SubscriptionListPresentation.displayedSubscriptions(
                in: displayOrder,
                states: states,
                pending: [.codex]
            ) == displayOrder
        )
        #expect(
            SubscriptionListPresentation.availableSubscriptions(
                in: displayOrder,
                states: states,
                pending: [.codex]
            ).isEmpty
        )
    }

    @Test func subscriptionRowsKeepTheUsersDisplayOrder() {
        var states = CodingAgentStates()
        states[.claudeCode] = .loading

        #expect(
            SubscriptionListPresentation.displayedSubscriptions(
                in: [.codex, .claudeCode],
                states: states,
                pending: [.codex]
            ) == [.codex, .claudeCode]
        )
    }
}
