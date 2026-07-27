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
    /// One agent's slice of today's totals, for the hero tooltip's split.
    struct AgentTokens: Equatable {
        let label: String
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
            if let today = await reader.todayUsage(underProjectsRoot: root.path) {
                slices.append(AgentTokens(label: root.label, usage: today))
            }
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
