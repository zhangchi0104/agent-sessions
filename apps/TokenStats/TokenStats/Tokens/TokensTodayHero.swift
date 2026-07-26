//
//  TokensTodayHero.swift
//  TokenStats
//
//  Today's token consumption across every Coding Agent (Claude Code
//  transcripts + Codex rollouts) as one hero figure — every token in and out
//  of the model — large and bold at the top of the popover. Digit changes
//  roll with a slot-machine effect (`numericText`) as the count grows — or
//  just swap under Reduce Motion. The per-agent and input/output splits live
//  in the tooltip.
//

import SwiftUI

struct TokensTodayHero: View {
    /// Combined totals across every Coding Agent.
    let usage: TokenUsage
    /// Per-agent slices of today's totals, disclosed in the tooltip.
    let perAgent: [TokensTodayModel.AgentTokens]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { usage.totalTokens }

    private var breakdown: String {
        let split = perAgent
            .map { "\($0.label) \($0.usage.totalTokens.formatted())" }
            .joined(separator: " · ")
        return (split.isEmpty ? "" : split + " — ") + usage.breakdownDescription
    }

    var body: some View {
        // Leading-aligned like the content below, so the figure reads as the
        // window's opening line rather than a centered billboard.
        VStack(alignment: .leading, spacing: 4) {
            Text(count.formatted())
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(count)))
                .animation(reduceMotion ? nil : .snappy(duration: 0.6), value: count)
            Text("tokens today")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(breakdown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) tokens consumed today")
    }
}
