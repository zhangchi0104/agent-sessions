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
                                          roots: [TranscriptRoot(id: .claudeCode, label: "Agent", path: root.path)])
        #expect(odometer.selectedRange == .today)
    }

    /// The model outlives the popover — it is a `let` on the app delegate — so
    /// "not persisted" has to mean the *same* model reverts to Today when the
    /// tab is shown again. Constructing a second model and checking its default
    /// would pass no matter what the app does.
    ///
    /// The rows have to go with the range. Leaving a month's figures in place
    /// while the heading resets to Today is precisely the mislabelling the
    /// trailing `displayedRange` exists to prevent, just at the other end of
    /// the appearance.
    @Test func theSameModelRevertsToTodayOnTheNextAppearance() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [
            claudeUsageLine(id: "m1", input: 100, output: 50),
            claudeUsageLine(id: "old", input: 999, output: 999, daysAgo: 10),
        ])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [TranscriptRoot(id: .claudeCode, label: "Agent", path: root.path)])
        let first = Task { await odometer.observeWhileVisible() }
        #expect(await waitUntil { odometer.hasLoaded })
        odometer.select(.thirtyDays)
        #expect(await waitUntil { odometer.displayedRange == .thirtyDays })
        #expect(odometer.usage?.totalTokens == 150 + 1_998)

        // The tab goes away…
        first.cancel()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(odometer.selectedRange == .thirtyDays) // the model kept it

        // …and comes back. `observeWhileVisible` resets before its first await,
        // and the main actor runs it in order, so one yield is enough to land
        // exactly in the interval the bug lived in: after the reset, before any
        // scan could have replaced the rows.
        let second = Task { await odometer.observeWhileVisible() }
        defer { second.cancel() }
        await Task.yield()

        #expect(odometer.selectedRange == .today)
        #expect(odometer.displayedRange == .today)
        #expect(odometer.hasLoaded == false)
        #expect(odometer.perAgent.isEmpty) // not a month's figures under "Today"

        #expect(await waitUntil { odometer.hasLoaded })
        #expect(odometer.usage?.totalTokens == 150)
    }

    /// The rows on screen carry the range they were computed for, which is what
    /// the heading and the per-agent subtotals follow. Until a scan lands, that
    /// stays behind the selection rather than jumping ahead of the data.
    @Test func displayedRangeTrailsTheSelectionUntilTheScanLands() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [claudeUsageLine(id: "m1", input: 100, output: 50)])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [TranscriptRoot(id: .claudeCode, label: "Agent", path: root.path)])
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }
        #expect(await waitUntil { odometer.hasLoaded && odometer.displayedRange == .today })

        // `select` is synchronous up to the scan it spawns, so the trailing
        // state is observable without racing it.
        odometer.select(.thirtyDays)
        #expect(odometer.selectedRange == .thirtyDays)
        #expect(odometer.displayedRange == .today)   // the rows still describe Today
        #expect(odometer.pendingRange == .thirtyDays) // and the tab says so

        #expect(await waitUntil { odometer.displayedRange == .thirtyDays })
        #expect(odometer.pendingRange == nil)
    }

    /// Entries older than the selected range are excluded, so Today does not
    /// quietly report a month.
    @Test func todayExcludesOlderEntries() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [
            claudeUsageLine(id: "m1", input: 100, output: 50),
            claudeUsageLine(id: "old", input: 999, output: 999, daysAgo: 10),
        ])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [TranscriptRoot(id: .claudeCode, label: "Agent", path: root.path)])
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.hasLoaded && odometer.usage?.totalTokens == 150 })

        odometer.select(.thirtyDays)
        #expect(await waitUntil { odometer.usage?.totalTokens == 150 + 1_998 })
    }

    /// Each range sums exactly its own days. Without this the 7-day span could
    /// be any number of days at all and no test would notice.
    @Test func eachRangeSumsItsOwnDays() async throws {
        let root = try TempTranscripts("claude")
        try root.write("a.jsonl", [
            claudeUsageLine(id: "today", input: 10, output: 0),
            claudeUsageLine(id: "within-week", input: 200, output: 0, daysAgo: 3),
            claudeUsageLine(id: "outside-week", input: 3_000, output: 0, daysAgo: 9),
            claudeUsageLine(id: "outside-month", input: 40_000, output: 0, daysAgo: 40),
        ])

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [TranscriptRoot(id: .claudeCode, label: "Agent", path: root.path)])
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.hasLoaded && odometer.usage?.totalTokens == 10 })

        odometer.select(.sevenDays)
        #expect(await waitUntil { odometer.displayedRange == .sevenDays })
        #expect(odometer.usage?.totalTokens == 210)

        odometer.select(.thirtyDays)
        #expect(await waitUntil { odometer.displayedRange == .thirtyDays })
        #expect(odometer.usage?.totalTokens == 3_210)
    }

    /// Transcripts are append-only, so a file last modified before the range
    /// opened cannot hold an entry inside it. Skipping those files is what
    /// keeps a Today scan from reading a month of transcripts.
    @Test func filesUntouchedSinceBeforeTheRangeAreSkipped() async throws {
        let root = try TempTranscripts("claude")
        try root.write("old.jsonl", [claudeUsageLine(id: "old", input: 999, output: 0, daysAgo: 10)])
        try FileManager.default.setAttributes(
            [.modificationDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date()],
            ofItemAtPath: root.url.appendingPathComponent("old.jsonl").path
        )

        let odometer = TokenOdometerModel(reader: TranscriptTokenReader(),
                                          roots: [TranscriptRoot(id: .claudeCode, label: "Agent", path: root.path)])
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.hasLoaded })
        #expect(odometer.usage == nil) // nothing today, and the file was never opened

        odometer.select(.thirtyDays)
        #expect(await waitUntil { odometer.usage?.totalTokens == 999 })
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
                                          roots: [TranscriptRoot(id: .claudeCode, label: "Agent", path: root.path)])
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }
        #expect(await waitUntil { odometer.hasLoaded })

        // Three scans are now in flight, two of them for ranges already
        // abandoned. Only the last selection may reach the published rows.
        odometer.select(.thirtyDays)
        odometer.select(.today)
        odometer.select(.thirtyDays)

        #expect(await waitUntil { odometer.displayedRange == .thirtyDays })
        #expect(odometer.pendingRange == nil)
        #expect(odometer.usage?.totalTokens == 150 + 1_998)

        // And it stays there: an abandoned scan landing late would drag the
        // displayed range back behind the selection.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(odometer.displayedRange == .thirtyDays)
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
            roots: [TranscriptRoot(id: .claudeCode, label: "Claude Code", path: busy.path),
                    TranscriptRoot(id: .codex, label: "Codex", path: idle.path)]
        )
        let task = Task { await odometer.observeWhileVisible() }
        defer { task.cancel() }

        #expect(await waitUntil { odometer.perAgent.count == 2 })
        // The busy agent really did parse, so an empty Codex group is a
        // measurement rather than the whole scan having come back blank.
        let busySlice = try #require(odometer.perAgent.first { $0.label == "Claude Code" })
        #expect(busySlice.usage.totalTokens == 150)
        let idleSlice = try #require(odometer.perAgent.first { $0.label == "Codex" })
        #expect(idleSlice.byModel.isEmpty)
        #expect(idleSlice.usage.totalTokens == 0)
    }
}
