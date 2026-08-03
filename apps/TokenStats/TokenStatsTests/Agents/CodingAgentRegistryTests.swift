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

/// What one registered Coding Agent is expected to publish. Internal rather
/// than private only because `@Test(arguments:)` surfaces it in the test's
/// signature.
struct AgentFacts: Sendable {
    let id: CodingAgentID
    let displayName: String
    let shortLabel: String
    let signInStyle: SignInStyle
    /// Gauge slots in display order.
    let windowIdentities: [UsageWindowIdentity]
    /// The slot drawn larger, or nil when every window is equal.
    let emphasizedWindow: UsageWindowIdentity?
    /// Appended to the user's home directory.
    let transcriptSubpath: String
}

private let expectedAgents: [AgentFacts] = [
    AgentFacts(id: .claudeCode,
               displayName: "Claude Code",
               shortLabel: "C",
               signInStyle: .pasteCode,
               windowIdentities: [.weekly, .shortTerm, .modelWeekly(model: "Fable")],
               emphasizedWindow: .shortTerm,
               transcriptSubpath: "/.claude/projects"),
    AgentFacts(id: .codex,
               displayName: "Codex",
               shortLabel: "X",
               signInStyle: .selfCompleting,
               windowIdentities: [],
               emphasizedWindow: nil,
               transcriptSubpath: "/.codex/sessions"),
]

@MainActor
struct CodingAgentRegistryTests {

    private var englishLocalizer: AppLocalizer {
        AppLocalizer(locale: Locale(identifier: "en-US"))
    }

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
        let identities = layout.slots.map(\.identity)
        let emphasized = layout.slots.filter(\.emphasized).map(\.identity)

        #expect(identities == expected.windowIdentities)
        #expect(emphasized == [expected.emphasizedWindow].compactMap { $0 })
    }

    @Test(arguments: expectedAgents)
    func gaugeLayoutFillsEveryDeclaredSlotEvenWhenTheWindowIsMissing(_ expected: AgentFacts) {
        // Fixed layouts retain their declared geometry when a plan omits one
        // of those windows. Dynamic layouts declare no fixed slots.
        let layout = CodingAgentRegistry.agent(expected.id).gaugeLayout
        let empty = UsageSnapshot(windows: [], fetchedAt: Date())

        let items = layout.items(for: empty, localizer: englishLocalizer)
        let titles = items.map(\.title)
        let enabled = items.map(\.isEnabled)
        let emphasized = items.filter(\.emphasized).map(\.identity)

        #expect(items.map(\.identity) == expected.windowIdentities)
        #expect(titles == expected.windowIdentities.map(\.fallbackTitle))
        #expect(enabled == titles.map { _ in false })
        #expect(emphasized == [expected.emphasizedWindow].compactMap { $0 })
    }

    @Test func codexGaugeLayoutUsesOnlyReturnedWindows() {
        let layout = CodingAgentRegistry.agent(.codex).gaugeLayout
        let weekly = UsageWindow(identity: .weekly, percentConsumed: 18,
                                 resetAt: Date(timeIntervalSince1970: 1717300000))

        let weeklyOnly = layout.items(
            for: UsageSnapshot(windows: [weekly], fetchedAt: Date()),
            localizer: englishLocalizer
        )

        #expect(weeklyOnly.map(\.title) == ["Weekly"])
        #expect(weeklyOnly.allSatisfy { $0.isEnabled })

        let short = UsageWindow(identity: .shortTerm, percentConsumed: 42,
                                resetAt: Date(timeIntervalSince1970: 1716800000))
        let both = layout.items(
            for: UsageSnapshot(windows: [short, weekly], fetchedAt: Date()),
            localizer: englishLocalizer
        )

        #expect(both.map(\.title) == ["5-hour", "Weekly"])
        #expect(both.allSatisfy { $0.isEnabled })
    }

    @Test(arguments: expectedAgents)
    func gaugeLayoutReadsEachWindowFromTheSnapshotByIdentity(_ expected: AgentFacts) {
        // A distinct, identity-keyed figure per window, so a slot that picked the
        // wrong window shows up as the wrong number rather than passing.
        func consumed(for identity: UsageWindowIdentity) -> Double {
            Double(((expected.windowIdentities.firstIndex(of: identity) ?? 0) * 10) + 5)
        }
        // Deliberately REVERSED, i.e. not in slot order — the real parsers don't
        // emit it that way (Claude Code's yields 5-hour, Weekly, Fable while its
        // layout draws Weekly, 5-hour, Fable), and a fixture in slot order would
        // pass even for an implementation that ignored slots entirely and mapped
        // the snapshot straight through.
        let windows = expected.windowIdentities.reversed().map { identity in
            UsageWindow(identity: identity, percentConsumed: consumed(for: identity),
                        resetAt: Date(timeIntervalSince1970: 1716800000))
        }
        let layout = CodingAgentRegistry.agent(expected.id).gaugeLayout

        let items = layout.items(
            for: UsageSnapshot(windows: windows, fetchedAt: Date()),
            localizer: englishLocalizer
        )
        let enabled = items.map(\.isEnabled)
        // Slot order is the layout's, not the snapshot's, and each slot carries
        // the figure belonging to its own semantic identity.
        let remaining = items.map(\.percentRemaining)
        let expectedRemaining = expected.windowIdentities.map { 100 - consumed(for: $0) }

        #expect(items.map(\.identity) == expected.windowIdentities)
        #expect(items.map(\.title) == expected.windowIdentities.map(\.fallbackTitle))
        #expect(enabled == expected.windowIdentities.map { _ in true })
        #expect(remaining == expectedRemaining)
    }

    @Test func fixedGaugeLayoutDoesNotMatchByFallbackTitle() throws {
        let layout = CodingAgentRegistry.agent(.claudeCode).gaugeLayout
        // Both identities currently fall back to the same English title. Only
        // the semantic short-term identity may fill Claude's center slot.
        let sameTitleDifferentIdentity = UsageWindow(
            identity: .duration(seconds: 5 * 60 * 60),
            percentConsumed: 42,
            resetAt: nil
        )

        let items = layout.items(
            for: UsageSnapshot(
                windows: [sameTitleDifferentIdentity],
                fetchedAt: Date()
            ),
            localizer: englishLocalizer
        )
        let shortTerm = try #require(items.first { $0.identity == .shortTerm })

        #expect(shortTerm.title == "5-hour")
        #expect(shortTerm.isEnabled == false)
    }

    @Test func shortLabelsAreDistinctSoTheMenuBarStaysReadable() {
        let labels = CodingAgentRegistry.all.map(\.shortLabel)
        let distinct = Set(labels)

        #expect(distinct.count == labels.count)
    }
}
