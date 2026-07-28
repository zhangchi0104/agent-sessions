//
//  TokensTodayModel.swift
//  TokenStats
//
//  Owns the Tokens Today hero figure at the top of the popover: token
//  usage summed across every Coding Agent's local files touched today —
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
final class TokensTodayModel {
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

    /// Today's combined totals (all agents), or nil when nothing was consumed
    /// today or the source directories are unreadable.
    private(set) var usage: TokenUsage?
    /// Per-agent slices of today's totals, in `roots` order; agents with no
    /// usage today are omitted.
    private(set) var perAgent: [AgentTokens] = []

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

    func refresh() async {
        // One scan per agent root; assigning after all awaits keeps the
        // published values consistent with each other.
        var slices: [AgentTokens] = []
        for root in roots {
            let byModel = await reader.todayBreakdown(underProjectsRoot: root.path)
            guard byModel.isEmpty == false else { continue }
            var total = TokenUsage()
            for usage in byModel.values { total.add(usage) }
            let rows = byModel
                .map { ModelTokens(model: $0.key, usage: $0.value) }
                .sorted { ($0.usage.totalTokens, $1.model) > ($1.usage.totalTokens, $0.model) }
            slices.append(AgentTokens(label: root.label, usage: total, byModel: rows))
        }
        perAgent = slices
        usage = slices.reduce(into: nil as TokenUsage?) { combined, slice in
            var sum = combined ?? TokenUsage()
            sum.add(slice.usage)
            combined = sum
        }
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
