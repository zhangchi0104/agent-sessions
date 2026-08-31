//
//  SubscriptionListPresentationTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

struct SubscriptionListPresentationTests {
    private let displayOrder: [CodingAgentID] = [.claudeCode, .codex]

    @Test func signedOutSubscriptionsAreAvailableInsteadOfDisplayed() {
        let states = CodingAgentSessionStates()

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
        var states = CodingAgentSessionStates()
        states[.claudeCode] = .valid(verifiedAt: .init(timeIntervalSince1970: 1_716_700_000))

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
        var states = CodingAgentSessionStates()
        states[.claudeCode] = .valid(verifiedAt: .init(timeIntervalSince1970: 1_716_700_000))

        #expect(
            SubscriptionListPresentation.displayedSubscriptions(
                in: [.codex, .claudeCode],
                states: states,
                pending: [.codex]
            ) == [.codex, .claudeCode]
        )
    }

    @Test func sessionsThatNeedRecoveryStayVisibleAndCannotBeAddedAgain() {
        var states = CodingAgentSessionStates()
        states[.claudeCode] = .reauthenticationRequired(reason: .invalidGrant)
        states[.codex] = .temporarilyUnverifiable(lastVerifiedAt: nil)

        #expect(
            SubscriptionListPresentation.displayedSubscriptions(
                in: displayOrder,
                states: states,
                pending: []
            ) == displayOrder
        )
        #expect(
            SubscriptionListPresentation.availableSubscriptions(
                in: displayOrder,
                states: states,
                pending: []
            ).isEmpty
        )
    }
}
