//
//  CodingAgentRegistryTests.swift
//  TokenStatsTests
//
//  The registry is the single declaration of every per-agent fact, so this
//  table is the specification of what each Coding Agent publishes. A new agent
//  fails these until it declares all of it; a changed fact fails them until the
//  change is deliberate.
//

import Testing
import Foundation
@testable import TokenStats

/// What one registered Coding Agent is expected to publish. Internal rather
/// than private only because `@Test(arguments:)` surfaces it in the test's
/// signature.
struct AgentFacts: Sendable {
    let id: CodingAgentID
    let displayName: String
    let shortLabel: String
    let signInStyle: SignInStyle
    /// Gauge slots in display order.
    let windowLabels: [String]
    /// The slot drawn larger, or nil when every window is equal.
    let emphasizedWindow: String?
    /// Appended to the user's home directory.
    let transcriptSubpath: String
}

private let expectedAgents: [AgentFacts] = [
    AgentFacts(id: .claudeCode,
               displayName: "Claude Code",
               shortLabel: "C",
               signInStyle: .pasteCode,
               windowLabels: ["Weekly", "5-hour", "Fable"],
               emphasizedWindow: "5-hour",
               transcriptSubpath: "/.claude/projects"),
    AgentFacts(id: .codex,
               displayName: "Codex",
               shortLabel: "X",
               signInStyle: .selfCompleting,
               windowLabels: ["5-hour", "Weekly"],
               emphasizedWindow: nil,
               transcriptSubpath: "/.codex/sessions"),
]

@MainActor
struct CodingAgentRegistryTests {

    @Test func registryCoversEveryCodingAgentExactlyOnce() {
        let registered = CodingAgentRegistry.all.map(\.id)

        #expect(Set(registered) == Set(CodingAgentID.allCases))
        #expect(registered.count == CodingAgentID.allCases.count)
    }

    @Test func everyRegisteredAgentIsInThisTest() {
        // Otherwise a new agent could join the registry and skip the table below.
        let tabled = Set(expectedAgents.map(\.id))
        let registered = Set(CodingAgentRegistry.all.map(\.id))

        #expect(tabled == registered)
    }

    @Test(arguments: expectedAgents)
    func agentPublishesItsFacts(_ expected: AgentFacts) {
        let agent = CodingAgentRegistry.agent(expected.id)

        #expect(agent.id == expected.id)
        #expect(agent.displayName == expected.displayName)
        #expect(agent.shortLabel == expected.shortLabel)
        #expect(agent.signInStyle == expected.signInStyle)
        #expect(agent.transcriptRoot == realHomeDirectory() + expected.transcriptSubpath)
    }

    @Test(arguments: expectedAgents)
    func agentPublishesItsGaugeLayout(_ expected: AgentFacts) {
        let layout = CodingAgentRegistry.agent(expected.id).gaugeLayout
        let labels = layout.slots.map(\.label)
        let emphasized = layout.slots.filter(\.emphasized).map(\.label)

        #expect(labels == expected.windowLabels)
        #expect(emphasized == [expected.emphasizedWindow].compactMap { $0 })
    }

    @Test(arguments: expectedAgents)
    func gaugeLayoutFillsEveryDeclaredSlotEvenWhenTheWindowIsMissing(_ expected: AgentFacts) {
        // A plan that doesn't expose one of the windows must still get a slot,
        // so an absent window leaves a placeholder rather than collapsing the row.
        let layout = CodingAgentRegistry.agent(expected.id).gaugeLayout
        let empty = UsageSnapshot(windows: [], fetchedAt: Date())

        let items = layout.items(for: empty)
        let titles = items.map(\.title)
        let enabled = items.map(\.isEnabled)
        let emphasized = items.filter(\.emphasized).map(\.title)

        #expect(titles == expected.windowLabels)
        #expect(enabled == titles.map { _ in false })
        #expect(emphasized == [expected.emphasizedWindow].compactMap { $0 })
    }

    @Test(arguments: expectedAgents)
    func gaugeLayoutReadsEachWindowFromTheSnapshotByLabel(_ expected: AgentFacts) {
        // A distinct, label-keyed figure per window, so a slot that picked the
        // wrong window shows up as the wrong number rather than passing.
        func consumed(for label: String) -> Double {
            Double(((expected.windowLabels.firstIndex(of: label) ?? 0) * 10) + 5)
        }
        // Deliberately REVERSED, i.e. not in slot order — the real parsers don't
        // emit it that way (Claude Code's yields 5-hour, Weekly, Fable while its
        // layout draws Weekly, 5-hour, Fable), and a fixture in slot order would
        // pass even for an implementation that ignored slots entirely and mapped
        // the snapshot straight through.
        let windows = expected.windowLabels.reversed().map { label in
            UsageWindow(label: label, percentConsumed: consumed(for: label),
                        resetAt: Date(timeIntervalSince1970: 1716800000))
        }
        let layout = CodingAgentRegistry.agent(expected.id).gaugeLayout

        let items = layout.items(for: UsageSnapshot(windows: windows, fetchedAt: Date()))
        let titles = items.map(\.title)
        let enabled = items.map(\.isEnabled)
        // Slot order is the layout's, not the snapshot's, and each slot carries
        // the figure belonging to its own label.
        let remaining = items.map(\.percentRemaining)
        let expectedRemaining = expected.windowLabels.map { 100 - consumed(for: $0) }

        #expect(titles == expected.windowLabels)
        #expect(enabled == titles.map { _ in true })
        #expect(remaining == expectedRemaining)
    }

    @Test func shortLabelsAreDistinctSoTheMenuBarStaysReadable() {
        let labels = CodingAgentRegistry.all.map(\.shortLabel)
        let distinct = Set(labels)

        #expect(distinct.count == labels.count)
    }
}
