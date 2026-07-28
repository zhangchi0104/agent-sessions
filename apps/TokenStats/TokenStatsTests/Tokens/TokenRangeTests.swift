//
//  TokenRangeTests.swift
//  TokenStatsTests
//
//  The Token Odometer's range control. Today is effectively instant, so it is
//  the default and a popover never waits on opening; the longer ranges are
//  always a deliberate switch. While one is scanning the table keeps the rows
//  it has — and keeps the range they belong to, so it never labels one range's
//  numbers with another range's name.
//

import Foundation
import Testing
@testable import TokenStats

@MainActor
struct TokenRangeTests {
    @Test func defaultsToToday() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [(label: "Agent", path: root.path)])
        #expect(odometer.selectedRange == .today)
    }

    /// A fresh observation cycle starts from Today — the range is deliberately
    /// not remembered, so a 30-day figure can never be read as today's.
    @Test func theRangeIsNotRememberedAcrossObservation() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [(label: "Agent", path: root.path)])
        odometer.select(.thirtyDays)
        #expect(odometer.selectedRange == .thirtyDays)

        let fresh = TokenOdometerModel(reader: TranscriptTokenReader(),
                                       roots: [(label: "Agent", path: root.path)])
        #expect(fresh.selectedRange == .today)
    }

    /// The rows on screen carry the range they were computed for, which is what
    /// the heading and the per-agent subtotals follow. Until a scan lands, that
    /// stays behind the selection rather than jumping ahead of the data.
    @Test func displayedRangeTrailsTheSelectionUntilTheScanLands() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [(label: "Agent", path: root.path)])
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }
        #expect(await waitUntil { odometer.displayedRange == .today })

        odometer.select(.thirtyDays)
        #expect(odometer.selectedRange == .thirtyDays)
        // The rows still describe Today until the 30-day scan replaces them.
        #expect(await waitUntil { odometer.displayedRange == .thirtyDays })
    }

    /// Entries older than the selected window are excluded, so Today does not
    /// quietly report a month.
    @Test func todayExcludesOlderEntries() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [
            claudeUsageLine(id: "m1", input: 100, output: 50),
            claudeUsageLine(id: "old", input: 999, output: 999, daysAgo: 10),
        ])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [(label: "Agent", path: root.path)])
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.usage?.totalTokens == 150 })

        odometer.select(.thirtyDays)
        #expect(await waitUntil { odometer.usage?.totalTokens == 150 + 1_998 })
    }

    /// A scan for a range the user has moved off must not land — it would park
    /// the displayed range behind the selection with nothing left running, and
    /// the progress cue would never resolve.
    @Test func aScanForAnAbandonedRangeDoesNotLand() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [
            claudeUsageLine(id: "m1", input: 100, output: 50),
            claudeUsageLine(id: "old", input: 999, output: 999, daysAgo: 10),
        ])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [(label: "Agent", path: root.path)])
        odometer.select(.thirtyDays)
        // A refresh captured while Today was selected completes late.
        odometer.select(.today)
        odometer.select(.thirtyDays)

        #expect(await waitUntil { odometer.displayedRange == .thirtyDays })
        #expect(odometer.pendingRange == nil)
        #expect(odometer.usage?.totalTokens == 150 + 1_998)
    }

    /// A Coding Agent with nothing in range is reported as present-and-empty,
    /// not omitted — an empty group is an everyday state and says so in words.
    @Test func anAgentWithNoUsageInRangeIsStillListed() async throws {
        let busy = try TempTranscripts("claude")
        try busy.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])
        let idle = try TempTranscripts("codex")

        let odometer = TokenOdometerModel(
            reader: TranscriptTokenReader(),
            roots: [(label: "Claude Code", path: busy.path), (label: "Codex", path: idle.path)]
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.perAgent.count == 2 })
        let idleSlice = try #require(odometer.perAgent.first { $0.label == "Codex" })
        #expect(idleSlice.byModel.isEmpty)
        #expect(idleSlice.usage.totalTokens == 0)
    }
}
