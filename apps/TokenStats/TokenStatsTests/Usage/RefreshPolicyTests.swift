//
//  RefreshPolicyTests.swift
//  TokenStatsTests
//

import Testing
import Foundation
@testable import TokenStats

struct RefreshPolicyTests {

    private let base: TimeInterval = 30 * 60

    @Test func timerWithNoPriorFetchFetchesNow() {
        let decision = RefreshPolicy.decide(
            trigger: .timer,
            lastFetch: nil,
            now: Date(),
            consecutiveFailures: 0
        )

        #expect(decision.shouldFetch)
        #expect(decision.nextInterval == base)
    }

    @Test func timerNotDueWhenLastFetchRecent() {
        let now = Date()
        let decision = RefreshPolicy.decide(
            trigger: .timer,
            lastFetch: now.addingTimeInterval(-base + 60), // 1 min short of due
            now: now,
            consecutiveFailures: 0
        )

        #expect(!decision.shouldFetch)
    }

    @Test func timerDueWhenIntervalElapsed() {
        let now = Date()
        let decision = RefreshPolicy.decide(
            trigger: .timer,
            lastFetch: now.addingTimeInterval(-base - 1),
            now: now,
            consecutiveFailures: 0
        )

        #expect(decision.shouldFetch)
    }

    @Test(arguments: [RefreshTrigger.popoverOpen, .wake, .manual])
    func nonTimerTriggersAlwaysFetchEvenWhenRecentlyFetched(trigger: RefreshTrigger) {
        let now = Date()
        let decision = RefreshPolicy.decide(
            trigger: trigger,
            lastFetch: now.addingTimeInterval(-5), // fetched 5s ago, timer wouldn't fire
            now: now,
            consecutiveFailures: 0
        )

        #expect(decision.shouldFetch)
    }

    @Test func backoffDoublesIntervalPerConsecutiveFailure() {
        let now = Date()
        func interval(failures: Int) -> TimeInterval {
            RefreshPolicy.decide(trigger: .timer, lastFetch: now, now: now,
                                 consecutiveFailures: failures).nextInterval
        }

        #expect(interval(failures: 0) == base)       // healthy
        #expect(interval(failures: 1) == base * 2)
        #expect(interval(failures: 2) == base * 4)
        #expect(interval(failures: 3) == base * 8)
    }

    @Test func timerDuenessUsesBackedOffIntervalAfterFailures() {
        let now = Date()
        // Fetched just over the base interval ago: due if healthy, but with one
        // failure the effective interval is 2×base, so it's not due yet.
        let decision = RefreshPolicy.decide(
            trigger: .timer,
            lastFetch: now.addingTimeInterval(-base - 60),
            now: now,
            consecutiveFailures: 1
        )

        #expect(!decision.shouldFetch)
    }

    @Test func nextIntervalResetsToBaseOnSuccess() {
        // A successful fetch is conveyed by the caller passing 0 failures.
        let decision = RefreshPolicy.decide(
            trigger: .timer, lastFetch: nil, now: Date(), consecutiveFailures: 0
        )

        #expect(decision.nextInterval == base)
    }
}
