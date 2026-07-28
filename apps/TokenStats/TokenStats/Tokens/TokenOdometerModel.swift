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
    /// nil when nothing was consumed in it.
    private(set) var usage: TokenUsage?
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

    private let reader: TranscriptTokenReader
    /// The file roots to scan, one per Coding Agent. The app passes
    /// `CodingAgentRegistry.transcriptRoots`, so adding an agent adds a root
    /// (all this model needs beyond that is reader support for its format).
    private let roots: [(label: String, path: String)]
    /// Ticks when a watched transcript changes, driving a re-read (ADR-0003).
    private let changeSource: TranscriptChangeSource

    init(reader: TranscriptTokenReader,
         roots: [(label: String, path: String)],
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
        Task { await refresh() }
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
            slices.append(AgentTokens(label: root.label, usage: total, byModel: rows))
        }
        displayedRange = range
        perAgent = slices
        var combined = TokenUsage()
        for slice in slices { combined.add(slice.usage) }
        // Nil means "nothing in this range", which the tab words rather than
        // rendering as a table of zeroes.
        usage = combined.responseCount > 0 ? combined : nil
    }

    /// Seed today's totals, then re-read whenever the watched transcript files
    /// change. Drive from a SwiftUI `.task`, which cancels this when the
    /// popover closes (ADR-0003: watch only while visible).
    func observeWhileVisible() async {
        await refresh()
        for await _ in changeSource.ticks() {
            await refresh()
        }
    }
}
