//
//  TokenOdometerModel.swift
//  TokenStats
//
//  Owns the Token Odometer behind the popover's Tokens tab: token usage
//  broken down by Coding Agent and Model, over the range the user has
//  selected — Claude Code transcripts (all projects) and Codex session
//  rollouts. The sources are plain files written by other processes, so while
//  visible the model seeds once and then re-reads on each file-change tick
//  from a TranscriptChangeSource (ADR-0003) rather than polling; the shared
//  TranscriptTokenReader keeps each re-read cheap by only parsing newly
//  appended bytes.
//

import Foundation
import Observation

@MainActor
@Observable
final class TokenOdometerModel {
    /// One Coding Agent's slice of the Token Odometer: its total, and the
    /// per-Model rows beneath it, ordered by total descending.
    struct AgentTokens: Equatable {
        let id: CodingAgentID
        let label: String
        let usage: TokenUsage
        let byModel: [ModelTokens]
    }

    /// One Model's row within a Coding Agent.
    struct ModelTokens: Equatable {
        let model: ModelName
        let usage: TokenUsage
    }

    /// Combined totals across every Coding Agent for the displayed range, or
    /// nil when nothing was consumed in it. Derived, not stored: the tab shows
    /// no grand total, so nothing on screen depends on it — it exists as a
    /// summary for callers that want one, and cannot drift from `perAgent`.
    var usage: TokenUsage? {
        var combined = TokenUsage()
        for slice in perAgent { combined.add(slice.usage) }
        return combined.responseCount > 0 ? combined : nil
    }
    /// Per-agent slices in `roots` order. An agent with no usage in range is
    /// listed with an empty breakdown rather than omitted — a quiet day is an
    /// ordinary state, and the tab says so in words instead of dropping a row.
    private(set) var perAgent: [AgentTokens] = []

    /// The range the user has asked for. Its initial value comes from the
    /// persisted Appearance preference, and the view writes every later
    /// selection back there.
    private(set) var selectedRange: TokenRange
    /// The range the rows on screen were computed for. It trails `selectedRange`
    /// while a longer scan runs, so the heading and the per-agent subtotals
    /// never label one range's numbers with another range's name.
    private(set) var displayedRange: TokenRange
    /// The range being scanned right now, if the displayed rows are stale.
    var pendingRange: TokenRange? { selectedRange == displayedRange ? nil : selectedRange }
    /// False until the first scan of this appearance lands, so the very first
    /// render shows a progress cue rather than a bare column header.
    private(set) var hasLoaded = false

    private let reader: TranscriptTokenReader
    /// The file roots to scan, one per Coding Agent. The app passes
    /// `CodingAgentRegistry.transcriptRoots`, so adding an agent adds a root
    /// (all this model needs beyond that is reader support for its format).
    private let roots: [TranscriptRoot]
    /// Ticks when a watched transcript changes, driving a re-read (ADR-0003).
    private let changeSource: TranscriptChangeSource

    /// Re-orders the published slices into the user's Appearance order. Set by
    /// the view that knows it; registry order until then.
    var displayOrder: [CodingAgentID] = []
    /// The scan started by a range change, tracked so it can be cancelled when
    /// the tab goes away — an unstructured task would outlive the popover,
    /// which ADR-0003 exists to prevent. `refresh()` checks for cancellation
    /// between roots, so the walk stops at the next root boundary rather than
    /// mid-file.
    private var rangeScan: Task<Void, Never>?
    /// Bumped by each appearance of the tab. The outgoing appearance's cleanup
    /// must not cancel a scan the incoming one has already started, and the two
    /// overlap: SwiftUI can run the new `.task` before the old one unwinds.
    private var appearance = 0

    init(reader: TranscriptTokenReader,
         roots: [TranscriptRoot],
         initialRange: TokenRange = .today,
         changeSource: any TranscriptChangeSource) {
        self.reader = reader
        self.roots = roots
        self.selectedRange = initialRange
        self.displayedRange = initialRange
        self.changeSource = changeSource
    }

    /// Ask for a different range. The rows on screen stay — dimmed by the
    /// view — until the scan lands, so switching never empties the tab.
    func select(_ range: TokenRange) {
        guard range != selectedRange else { return }
        selectedRange = range
        rangeScan?.cancel()
        rangeScan = Task { await refresh() }
    }

    func refresh() async {
        let range = selectedRange
        // One clock reading for the whole refresh: resolving the range per root
        // would let a scan running across local midnight report one agent over
        // today and the next over yesterday, side by side, as a comparison.
        let now = Date()
        // One scan per agent root; assigning after all awaits keeps the
        // published values consistent with each other, and keeps the rows and
        // the range they describe from ever disagreeing.
        var slices: [AgentTokens] = []
        for root in roots {
            // The reader's walk is synchronous, so cancellation lands here,
            // between roots — close enough that a closed popover stops paying
            // for the roots it has not reached.
            if Task.isCancelled { return }
            let byModel = await reader.breakdown(underTranscriptRoot: root.path, range: range, now: now)
            var total = TokenUsage()
            for usage in byModel.values { total.add(usage) }
            let rows = byModel
                .map { ModelTokens(model: $0.key, usage: $0.value) }
                .sorted { left, right in
                    // Biggest first, and alphabetical between equals so the
                    // order of two idle Models doesn't shuffle between scans.
                    if left.usage.totalTokens != right.usage.totalTokens {
                        return left.usage.totalTokens > right.usage.totalTokens
                    }
                    return left.model < right.model
                }
            slices.append(AgentTokens(id: root.id, label: root.label, usage: total, byModel: rows))
        }
        // A slower scan for a range the user has since moved off must not
        // land: it would overwrite fresher rows and, worse, park displayedRange
        // behind a selection with no scan left running — a progress cue that
        // never resolves. The exception is the first scan of an appearance:
        // nothing is on screen yet, so its rows are better than the blank the
        // pending scan would otherwise leave for several seconds, and the
        // heading still names the range they actually describe.
        guard range == selectedRange || hasLoaded == false else { return }
        displayedRange = range
        hasLoaded = true
        // Registry order is the scan order; the popover shows the user's.
        let rank = Dictionary(uniqueKeysWithValues: displayOrder.enumerated().map { ($1, $0) })
        perAgent = slices.enumerated()
            .sorted { left, right in
                (rank[left.element.id] ?? left.offset) < (rank[right.element.id] ?? right.offset)
            }
            .map(\.element)
    }

    /// Seed the persisted range's totals, then re-read whenever the watched
    /// transcript files change. Drive from a SwiftUI `.task`, which cancels
    /// this when the popover closes (ADR-0003: watch only while visible).
    func observeWhileVisible() async {
        // The selection survives tab and process restarts. Rows are still
        // dropped on each appearance because the watcher sleeps while hidden;
        // a fresh seed makes the first displayed reading current and prevents
        // stale rows from looking live during a longer-range scan.
        appearance += 1
        let epoch = appearance
        displayedRange = selectedRange
        perAgent = []
        hasLoaded = false
        // Only tear down a scan this appearance started: SwiftUI can run the
        // next appearance's `.task` before this one unwinds, and cancelling
        // then would kill the scan the user is currently waiting on.
        defer { if appearance == epoch { rangeScan?.cancel() } }
        // Arm the watch before seeding rather than after: a transcript written
        // while the first scan runs would otherwise never tick, and the tab
        // would settle on figures that were already stale when they landed.
        let ticks = changeSource.ticks()
        await refresh()
        for await _ in ticks {
            await refresh()
        }
    }
}
