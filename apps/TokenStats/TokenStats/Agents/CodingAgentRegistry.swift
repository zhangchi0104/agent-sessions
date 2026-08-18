//
//  CodingAgentRegistry.swift
//  TokenStats
//
//  The Coding Agents TokenStats tracks. Adding one is a CodingAgentIntegration
//  conformance, a case on CodingAgentID, and a line in `all`.
//

import Foundation

/// One Coding Agent's scan root, carrying the id its display order is keyed by.
struct TranscriptRoot: Equatable {
    let id: CodingAgentID
    let label: String
    let path: String
}

enum CodingAgentRegistry {
    /// One entry per Coding Agent, in the order they lead the popover before
    /// the user's Appearance preferences reorder them. `CodingAgentRegistryTests`
    /// asserts this covers `CodingAgentID.allCases` exactly once each.
    static let all: [any CodingAgentIntegration] = [
        ClaudeCodeIntegration(),
        CodexIntegration(),
        CursorIntegration(),
    ]

    /// Traps on a duplicate id, so two integrations can never claim one agent.
    private static let byID: [CodingAgentID: any CodingAgentIntegration] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func agent(_ id: CodingAgentID) -> any CodingAgentIntegration {
        guard let agent = byID[id] else {
            preconditionFailure("No CodingAgentIntegration registered for \(id.rawValue)")
        }
        return agent
    }

    /// The Token Odometer scan roots, one per Coding Agent, in registry order.
    /// The id travels with each root so a consumer can re-order them into the
    /// user's Appearance display order, which is what the popover shows.
    static var transcriptRoots: [TranscriptRoot] {
        all.compactMap { integration in
            integration.transcriptRoot.map {
                TranscriptRoot(id: integration.id, label: integration.displayName, path: $0)
            }
        }
    }
}
