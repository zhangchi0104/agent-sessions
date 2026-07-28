//
//  TokensTabView.swift
//  TokenStats
//
//  The popover's Tokens tab: the Token Odometer for the selected range, as a
//  table grouped by Coding Agent then Model, four Token Kinds to a row with a
//  proportion bar tucked beneath. There is no combined total — per-agent
//  subtotals carry that role.
//
//  The colour key rides in the column header rather than a legend block: a
//  spelled-out legend measures 298pt against the 298pt this popover has, which
//  would make the wording of four labels a layout constraint. Full names live
//  in the header tooltips and in CONTEXT.md.
//

import SwiftUI

struct TokensTabView: View {
    let odometer: TokenOdometerModel

    /// Dimmed while a scan is in flight — either the first of this appearance,
    /// or a longer range the user switched to — so the tab shows a cue rather
    /// than a bare column header or a table that empties for several seconds.
    private var isScanning: Bool { odometer.pendingRange != nil || odometer.hasLoaded == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            rangePicker
            heading
            table
                .opacity(isScanning ? 0.45 : 1)
                .overlay(alignment: .top) { if isScanning { scanning } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Watches transcripts only while the Tokens tab is showing them;
        // SwiftUI cancels this when the tab (or the popover) goes away.
        .task { await odometer.observeWhileVisible() }
    }

    private var rangePicker: some View {
        Picker("Range", selection: Binding(
            get: { odometer.selectedRange },
            set: { odometer.select($0) }
        )) {
            ForEach(TokenRange.allCases, id: \.self) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Names the range the rows below actually describe — never the pending
    /// one. Switching to 30 days must not relabel today's numbers while the
    /// scan is still running.
    private var heading: some View {
        Text(odometer.displayedRange.label)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(.secondary)
    }

    /// The cue names what is being *read*, which is the pending range — the
    /// one thing on screen that may legitimately run ahead of the data.
    private var scanning: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Reading \((odometer.pendingRange ?? odometer.selectedRange).label.lowercased())…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var table: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(odometer.perAgent, id: \.label) { agent in
                agentGroup(agent)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("MODEL")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(TokenKind.allCases, id: \.self) { kind in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(kind.color)
                        .frame(width: 6, height: 6)
                    Text(kind.abbreviation)
                }
                .foregroundStyle(kind.color)
                .frame(width: 42, alignment: .trailing)
                .help(kind.name)
            }
        }
        .font(.system(size: 9.5, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private func agentGroup(_ agent: TokenOdometerModel.AgentTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(agent.label.uppercased())
                Spacer()
                if agent.byModel.isEmpty == false {
                    Text(TokenUsage.compact(agent.usage.totalTokens)).monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

            if agent.byModel.isEmpty {
                // An ordinary state, not an error: a day with no usage for this
                // agent says so rather than leaving a bare heading behind.
                Text("No usage in this range")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(agent.byModel, id: \.model) { row in
                    modelRow(row)
                }
            }
        }
    }

    private func modelRow(_ row: TokenOdometerModel.ModelTokens) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(row.model)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(TokenKind.allCases, id: \.self) { kind in
                    let amount = kind.amount(in: row.usage)
                    Text(amount > 0 ? TokenUsage.compact(amount) : "–")
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)

            ProportionBar(usage: row.usage)
        }
        .help(row.usage.kindBreakdown)
    }
}

/// The four Token Kinds as the table shows them, in the order their segments
/// run in the bar beneath each row — which is what lets the header double as
/// the colour key.
enum TokenKind: CaseIterable, Hashable {
    case directInput
    case output
    case cacheWrite
    case cacheRead

    var name: String {
        switch self {
        case .directInput: "Direct input"
        case .output: "Output"
        case .cacheWrite: "Cache write"
        case .cacheRead: "Cache read"
        }
    }

    var abbreviation: String {
        switch self {
        case .directInput: "IN"
        case .output: "OUT"
        case .cacheWrite: "C·W"
        case .cacheRead: "C·R"
        }
    }

    /// Cache read is most of almost every total, so it is the desaturated one;
    /// the small kinds keep the saturation that makes them visible in a 3pt bar.
    var color: Color {
        switch self {
        case .directInput: Color(red: 0.29, green: 0.60, blue: 0.94)
        case .output: Color(red: 0.22, green: 0.68, blue: 0.53)
        case .cacheWrite: Color(red: 0.85, green: 0.62, blue: 0.22)
        case .cacheRead: Color(red: 0.56, green: 0.52, blue: 0.75)
        }
    }

    func amount(in usage: TokenUsage) -> Int {
        switch self {
        case .directInput: usage.inputTokens
        case .output: usage.outputTokens
        case .cacheWrite: usage.cacheCreationTokens
        case .cacheRead: usage.cacheReadTokens
        }
    }
}

/// One row's composition, drawn flush beneath its figures so it doubles as the
/// row rule a dense table needs anyway. Codex rows show no cache-write segment,
/// which is how the absence becomes legible without prior knowledge.
private struct ProportionBar: View {
    let usage: TokenUsage

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(TokenKind.allCases, id: \.self) { kind in
                    let amount = kind.amount(in: usage)
                    if amount > 0 {
                        kind.color.frame(width: width(of: amount, in: geometry.size.width))
                    }
                }
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .accessibilityHidden(true)
    }

    private func width(of amount: Int, in total: CGFloat) -> CGFloat {
        guard usage.totalTokens > 0 else { return 0 }
        return total * CGFloat(amount) / CGFloat(usage.totalTokens)
    }
}

extension TokenUsage {
    /// Exact figures for the row tooltip, since the table itself is compacted.
    var kindBreakdown: String {
        TokenKind.allCases
            .map { "\($0.name) \($0.amount(in: self).formatted())" }
            .joined(separator: " · ")
    }
}
