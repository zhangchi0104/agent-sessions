//
//  CodingAgentRegistry.swift
//  TokenStats
//
//  The Coding Agents TokenStats tracks. Adding one is a CodingAgentIntegration
//  conformance, a case on CodingAgentID, and a line in `all`.
//

import Foundation

enum CodingAgentRegistry {
    /// One entry per Coding Agent, in the order they lead the popover before
    /// the user's Appearance preferences reorder them. `CodingAgentRegistryTests`
    /// asserts this covers `CodingAgentID.allCases` exactly once each.
    static let all: [any CodingAgentIntegration] = [
        ClaudeCodeIntegration(),
        CodexIntegration(),
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

    /// The Tokens Today scan roots, one per Coding Agent, in registry order.
    static var transcriptRoots: [(label: String, path: String)] {
        all.map { (label: $0.displayName, path: $0.transcriptRoot) }
    }
}
