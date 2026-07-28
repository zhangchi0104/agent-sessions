//
//  TokenOdometerModel.swift
//  TokenStats
//
//  Owns the Token Odometer behind the popover's Tokens tab: token usage
//  broken down by Coding Agent and Model, from local files touched today —
//  Claude Code transcripts (all projects) and Codex session rollouts. The
//  sources are plain files written by other processes, so while visible the
//  model seeds once and then re-reads on each file-change tick from a
//  TranscriptChangeSource (ADR-0003) rather than polling; the shared
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
        let model: String
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

    /// The range the user has asked for. Deliberately not persisted: a
    /// remembered 30-day selection would be read as today's figure on the next
    /// opening.
    private(set) var selectedRange: TokenRange = .today
    /// The range the rows on screen were computed for. It trails `selectedRange`
    /// while a longer scan runs, so the heading and the per-agent subtotals
    /// never label one range's numbers with another range's name.
    private(set) var displayedRange: TokenRange = .today
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
    /// the tab goes away — an unstructured task would keep walking the
    /// filesystem after the popover closed, which ADR-0003 exists to prevent.
    private var rangeScan: Task<Void, Never>?

    init(reader: TranscriptTokenReader,
         roots: [TranscriptRoot],
         changeSource: TranscriptChangeSource? = nil) {
        self.reader = reader
        self.roots = roots
        self.changeSource = changeSource ?? FSEventsTranscriptChangeSource(paths: roots.map(\.path))
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
        // One scan per agent root; assigning after all awaits keeps the
        // published values consistent with each other, and keeps the rows and
        // the range they describe from ever disagreeing.
        var slices: [AgentTokens] = []
        for root in roots {
            let byModel = await reader.breakdown(underProjectsRoot: root.path, range: range)
            var total = TokenUsage()
            for usage in byModel.values { total.add(usage) }
            let rows = byModel
                .map { ModelTokens(model: $0.key, usage: $0.value) }
                .sorted { ($0.usage.totalTokens, $1.model) > ($1.usage.totalTokens, $0.model) }
            slices.append(AgentTokens(id: root.id, label: root.label, usage: total, byModel: rows))
        }
        // A slower scan for a range the user has since moved off must not
        // land: it would overwrite fresher rows and, worse, park displayedRange
        // behind a selection with no scan left running — a progress cue that
        // never resolves.
        guard range == selectedRange else { return }
        displayedRange = range
        hasLoaded = true
        // Registry order is the scan order; the popover shows the user's.
        let rank = Dictionary(uniqueKeysWithValues: displayOrder.enumerated().map { ($1, $0) })
        perAgent = slices.enumerated()
            .sorted { rank[$0.element.id] ?? $0.offset < rank[$1.element.id] ?? $1.offset }
            .map(\.element)
    }

    /// Seed today's totals, then re-read whenever the watched transcript files
    /// change. Drive from a SwiftUI `.task`, which cancels this when the
    /// popover closes (ADR-0003: watch only while visible).
    func observeWhileVisible() async {
        // Each appearance starts on Today. The model outlives the popover, so
        // without this a 30-day selection would be waiting on the next opening
        // and its figure read as today's.
        selectedRange = .today
        displayedRange = .today
        hasLoaded = false
        defer { rangeScan?.cancel() }
        await refresh()
        for await _ in changeSource.ticks() {
            await refresh()
        }
    }
}
