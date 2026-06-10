//
//  UsageSnapshotParserTests.swift
//  TokenStatsTests
//
//  Shapes here reflect the real usage endpoint (empirically confirmed
//  2026-05-28, see docs/claude-code-integration.md): `utilization` is already
//  a percent (0–100), and `resets_at` is either an ISO-8601 timestamp string
//  or explicit null.
//

import Testing
import Foundation
@testable import TokenStats

struct UsageSnapshotParserTests {

    /// Epoch 42s, expressed the way the API expresses reset times.
    private let isoEpoch42 = "1970-01-01T00:00:42Z"
    private let isoEpoch99 = "1970-01-01T00:01:39Z" // 99s

    @Test func parsesFiveHourWindow() throws {
        let json = Data("""
        { "five_hour": { "utilization": 42.0, "resets_at": "\(isoEpoch42)" } }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.count == 1)
        let window = try #require(windows.first)
        #expect(window.percentConsumed == 42)
        #expect(window.resetAt == Date(timeIntervalSince1970: 42))
    }

    @Test func parsesBothWindowsWithPrimaryFirst() throws {
        let json = Data("""
        {
          "five_hour": { "utilization": 42.0, "resets_at": "\(isoEpoch42)" },
          "seven_day": { "utilization": 18.0, "resets_at": "\(isoEpoch99)" }
        }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.count == 2)
        #expect(windows[0].label == "5-hour")
        #expect(windows[0].percentConsumed == 42)
        #expect(windows[1].label == "Weekly")
        #expect(windows[1].percentConsumed == 18)
        #expect(windows[1].resetAt == Date(timeIntervalSince1970: 99))
    }

    @Test func returnsOnlyWeeklyWhenFiveHourAbsent() throws {
        let json = Data("""
        { "seven_day": { "utilization": 18.0, "resets_at": "\(isoEpoch42)" } }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.map(\.label) == ["Weekly"])
    }

    @Test func returnsEmptyWhenNoKnownWindows() throws {
        let json = Data(#"{ "overage": { "utilization": 10.0 } }"#.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.isEmpty)
    }

    @Test func dropsMalformedWindowButKeepsValidOnes() throws {
        // five_hour is present but missing resets_at — a broken block must not
        // sink the whole snapshot.
        let json = Data("""
        {
          "five_hour": { "utilization": 42.0 },
          "seven_day": { "utilization": 18.0, "resets_at": "\(isoEpoch42)" }
        }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.map(\.label) == ["Weekly"])
    }

    @Test func dropsWindowWithUnparseableResetTimestamp() throws {
        let json = Data("""
        { "five_hour": { "utilization": 42.0, "resets_at": "not-a-date" } }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.isEmpty)
    }

    @Test func keepsWindowsWhenResetTimestampIsNull() throws {
        let json = Data("""
        {
          "five_hour": { "utilization": 0.0, "resets_at": null },
          "seven_day": { "utilization": 0.0, "resets_at": null },
          "seven_day_oauth_apps": null,
          "seven_day_opus": null,
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null }
        }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.map(\.label) == ["5-hour", "Weekly"])
        #expect(windows.map(\.percentConsumed) == [0, 0])
        #expect(windows.allSatisfy { $0.resetAt == nil })
    }

    @Test func parsesCreditsFromExtraUsage() {
        // extra_usage amounts are cents: 5652 = $56.52 used of $155.00.
        let json = Data("""
        {
          "five_hour": { "utilization": 0.0, "resets_at": null },
          "extra_usage": {
            "is_enabled": true,
            "monthly_limit": 15500,
            "used_credits": 5652.0,
            "utilization": 36.46451612903226,
            "currency": "AUD"
          }
        }
        """.utf8)

        let credits = try? #require(UsageSnapshotParser.parseCredits(json))

        #expect(credits?.limitDollars == 155)
        #expect(credits?.remainingDollars == 98.48)
        #expect(credits?.currency == "AUD")
        #expect(credits.map { Int($0.percentRemaining.rounded()) } == 64)
    }

    @Test func returnsNoCreditsWhenExtraUsageDisabledOrAbsent() {
        let disabled = Data("""
        { "extra_usage": { "is_enabled": false, "monthly_limit": 15500 } }
        """.utf8)
        let absent = Data("""
        { "five_hour": { "utilization": 0.0, "resets_at": null } }
        """.utf8)

        #expect(UsageSnapshotParser.parseCredits(disabled) == nil)
        #expect(UsageSnapshotParser.parseCredits(absent) == nil)
    }

    @Test func ignoresExtraUsageWhenMeteredWindowsArePresent() throws {
        // On a usage-credit/AUD plan the 5-hour and weekly windows come back as
        // zero with null resets, while extra_usage carries a separate credit
        // quota — surfaced separately via parseCredits, not as a reset window.
        let json = Data("""
        {
          "five_hour": { "utilization": 0.0, "resets_at": null },
          "seven_day": { "utilization": 0.0, "resets_at": null },
          "seven_day_oauth_apps": null,
          "seven_day_opus": null,
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "seven_day_cowork": null,
          "seven_day_omelette": null,
          "tangelo": null,
          "iguana_necktie": null,
          "omelette_promotional": null,
          "extra_usage": {
            "is_enabled": true,
            "monthly_limit": 15500,
            "used_credits": 5652.0,
            "utilization": 36.46451612903226,
            "currency": "AUD",
            "disabled_reason": null
          }
        }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.map(\.label) == ["5-hour", "Weekly"])
        #expect(windows[0].percentConsumed == 0)
        #expect(windows[0].resetAt == nil)
        #expect(windows[1].percentConsumed == 0)
    }

    @Test func ignoresExtraUsageWhenNoUsageWindowsArePresent() throws {
        let json = Data("""
        {
          "extra_usage": {
            "is_enabled": true,
            "monthly_limit": 15500,
            "used_credits": 5652.0,
            "utilization": 36.46451612903226,
            "currency": "AUD"
          }
        }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.isEmpty)
    }

    @Test func throwsOnUnparseablePayload() {
        let json = Data("not json at all".utf8)

        #expect(throws: (any Error).self) {
            try UsageSnapshotParser.parse(json)
        }
    }

    @Test func parsesRealWorldResponse() throws {
        // Verbatim shape from the live endpoint: percent utilization, ISO-8601
        // reset timestamps with microseconds and an explicit +00:00 offset,
        // plus extra keys we ignore.
        let json = Data("""
        {
          "five_hour": { "utilization": 24.0, "resets_at": "2026-05-28T04:09:59.816765+00:00" },
          "seven_day": { "utilization": 18.0, "resets_at": "2026-05-28T06:00:00.816789+00:00" },
          "seven_day_oauth_apps": null
        }
        """.utf8)

        let windows = try UsageSnapshotParser.parse(json)

        #expect(windows.map(\.label) == ["5-hour", "Weekly"])
        #expect(windows[0].percentConsumed == 24)
        #expect(windows[1].percentConsumed == 18)
        // Both present means both ISO timestamps parsed (else they'd be dropped).
        let expectedFiveHour = ISO8601DateFormatter().date(from: "2026-05-28T04:09:59Z")
        let resetAt = try #require(windows[0].resetAt)
        #expect(abs(resetAt.timeIntervalSince(expectedFiveHour!)) < 1)
    }
}
