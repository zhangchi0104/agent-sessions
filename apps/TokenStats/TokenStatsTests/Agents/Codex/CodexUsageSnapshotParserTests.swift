//
//  CodexUsageSnapshotParserTests.swift
//  TokenStatsTests
//
//  Shapes here reflect Codex's `RateLimitStatusPayload` (read from the
//  open-source openai/codex CLI, see docs/codex-integration.md):
//  `used_percent` is an integer percent and `reset_at` is Unix epoch seconds.
//

import Testing
import Foundation

struct CodexUsageSnapshotParserTests {

    @Test func parsesPrimaryAndSecondaryWindows() throws {
        let json = Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window":   { "used_percent": 42, "limit_window_seconds": 18000,  "reset_at": 1716800000 },
            "secondary_window": { "used_percent": 18, "limit_window_seconds": 604800, "reset_at": 1717300000 }
          }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [.shortTerm, .weekly])
        #expect(windows.map(\.label) == ["5-hour", "Weekly"])
        #expect(windows[0].percentConsumed == 42)
        #expect(windows[0].resetAt == Date(timeIntervalSince1970: 1716800000))
        #expect(windows[1].percentConsumed == 18)
        #expect(windows[1].resetAt == Date(timeIntervalSince1970: 1717300000))
    }

    @Test func returnsOnlyPrimaryWhenSecondaryAbsent() throws {
        let json = Data("""
        {
          "rate_limit": {
            "primary_window": { "used_percent": 30, "reset_at": 1716800000 }
          }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [.shortTerm])
        #expect(windows[0].percentConsumed == 30)
    }

    @Test func namesAWeeklyWindowFromDurationEvenWhenItMovesToPrimary() throws {
        let json = Data("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 18,
              "limit_window_seconds": 604800,
              "reset_at": 1717300000
            }
          }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [.weekly])
        #expect(windows[0].percentConsumed == 18)
    }

    @Test func restoresARealFiveHourWindowWhenItsDurationReturns() throws {
        let json = Data("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 42,
              "limit_window_seconds": 18000,
              "reset_at": 1716800000
            },
            "secondary_window": {
              "used_percent": 18,
              "limit_window_seconds": 604800,
              "reset_at": 1717300000
            }
          }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [.shortTerm, .weekly])
    }

    @Test func describesOtherDurationsRatherThanTrustingTheirSlots() throws {
        let json = Data("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 11,
              "limit_window_seconds": 7200
            },
            "secondary_window": {
              "used_percent": 22,
              "limit_window_seconds": 259200
            }
          }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [
            .duration(seconds: 2 * 60 * 60),
            .duration(seconds: 3 * 24 * 60 * 60),
        ])
        #expect(windows.map(\.label) == ["2-hour", "3-day"])
    }

    @Test func fallsBackToTheSlotWhenAnOptionalDurationIsMalformed() throws {
        let json = Data("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 30,
              "limit_window_seconds": "unknown"
            }
          }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [.shortTerm])
        #expect(windows[0].percentConsumed == 30)
    }

    @Test func returnsEmptyWhenRateLimitIsNull() throws {
        // A usage-based/credits plan can report no rate-limit windows. The
        // provider treats an empty result as "no Usage Windows".
        let json = Data("""
        {
          "plan_type": "plus",
          "rate_limit": null,
          "credits": { "has_credits": true, "unlimited": false, "balance": "9.99" }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.isEmpty)
    }

    @Test func treatsMissingOrZeroResetAsUnavailable() throws {
        let json = Data("""
        {
          "rate_limit": {
            "primary_window":   { "used_percent": 0 },
            "secondary_window": { "used_percent": 5, "reset_at": 0 }
          }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [.shortTerm, .weekly])
        #expect(windows.allSatisfy { $0.resetAt == nil })
    }

    @Test func ignoresCreditsAndAdditionalRateLimits() throws {
        let json = Data("""
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": { "used_percent": 24, "reset_at": 1716800000 },
            "secondary_window": { "used_percent": 12, "reset_at": 1717300000 }
          },
          "credits": { "has_credits": true, "unlimited": false, "balance": "9.99" },
          "additional_rate_limits": [
            { "metered_feature": "codex_other", "limit_name": "codex_other",
              "rate_limit": { "primary_window": { "used_percent": 70, "reset_at": 1716900000 } } }
          ],
          "rate_limit_reached_type": { "type": "rate_limit_reached" }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [.shortTerm, .weekly])
        #expect(windows.map(\.percentConsumed) == [24, 12])
    }

    @Test func dropsMalformedWindowButKeepsValidOne() throws {
        // primary_window is present but missing used_percent — a broken block
        // must not sink the snapshot.
        let json = Data("""
        {
          "rate_limit": {
            "primary_window": { "limit_window_seconds": 18000 },
            "secondary_window": { "used_percent": 18, "reset_at": 1717300000 }
          }
        }
        """.utf8)

        let windows = try CodexUsageSnapshotParser.parse(json)

        #expect(windows.map(\.identity) == [.weekly])
        #expect(windows[0].percentConsumed == 18)
    }

    @Test func throwsOnUnparseablePayload() {
        let json = Data("not json at all".utf8)

        #expect(throws: (any Error).self) {
            try CodexUsageSnapshotParser.parse(json)
        }
    }
}
