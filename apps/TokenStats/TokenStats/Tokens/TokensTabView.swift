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
import AppKit

struct TokensTabView: View {
    let odometer: TokenOdometerModel

    /// How tall the table is allowed to grow before it scrolls instead. The
    /// popover has no height of its own — it is exactly as tall as its content
    /// — so without a ceiling a user with many Models gets a window taller
    /// than the screen. 11 Model rows measured ~539pt in the layout prototype.
    private static let tableHeightCap: CGFloat = 460

    @State private var tableHeight: CGFloat = 0

    /// Dimmed while a scan is in flight — either the first of this appearance,
    /// or a longer range the user switched to — so the tab shows a cue rather
    /// than a bare column header or a table that empties for several seconds.
    private var isScanning: Bool { odometer.pendingRange != nil || odometer.hasLoaded == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            rangePicker
            headingRow
            // The dim has to clear macOS's own disabled-text alpha: the rows it
            // covers are already drawn below full strength, and the two
            // multiply. Held rows are meant to read as *last* range's numbers,
            // not as a table that has gone blank.
            scrollingTable.opacity(isScanning ? 0.6 : 1)
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
        // Centred, not stretched. A segmented control on macOS draws at its
        // intrinsic width and centres itself in whatever frame it is given —
        // handing it a definite 300pt (measured, not guessed) leaves the
        // segments exactly this wide, so there is nothing to be gained by
        // measuring. It sits narrower than the table below it by design.
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Token Odometer range")
    }

    /// The heading names the range the rows below actually describe — never the
    /// pending one; switching to 30 days must not relabel today's numbers while
    /// the scan runs. The cue sits beside it rather than over the table, so it
    /// never lands on the column header, and it names the range being *read*,
    /// which is the one thing allowed to run ahead of the data.
    private var headingRow: some View {
        HStack(spacing: 6) {
            Text(odometer.displayedRange.label)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.4)
            Spacer(minLength: 8)
            if isScanning {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Reading \((odometer.pendingRange ?? odometer.selectedRange).label.lowercased())…")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.secondary)
        .frame(height: 14)
    }

    /// The table, clamped to `tableHeightCap` and scrolling past it. Measured
    /// rather than given a fixed frame: a ScrollView takes every point it is
    /// offered, which in a content-sized popover would pad a two-row table out
    /// to the full cap.
    private var scrollingTable: some View {
        ScrollView(.vertical) {
            table
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: TableHeightKey.self, value: geometry.size.height)
                    }
                )
        }
        .frame(height: min(max(tableHeight, 1), Self.tableHeightCap))
        .onPreferenceChange(TableHeightKey.self) { height in
            tableHeight = height
        }
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
                .accessibilityLabel(kind.name)
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
                    Text(TokenUsage.compact(agent.usage.totalTokens))
                        .monospacedDigit()
                        // The compacted subtotal rounds two agents 4% apart to
                        // the same figure; the exact one belongs within reach.
                        .help(agent.usage.totalTokens.formatted())
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(agent.byModel.isEmpty
                                ? Text(agent.label)
                                : Text("\(agent.label), \(agent.usage.totalTokens.formatted()) tokens"))

            if agent.byModel.isEmpty {
                // An ordinary state, not an error: an agent with nothing in the
                // selected range says so rather than leaving a bare heading.
                Text("No usage in this range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text(row.model.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                ForEach(TokenKind.allCases, id: \.self) { kind in
                    let amount = row.usage.amount(of: kind)
                    // The figures are the interface here, so they are the one
                    // thing in the tab drawn at full strength.
                    Text(amount > 0 ? TokenUsage.compact(amount) : "–")
                        .frame(width: 42, alignment: .trailing)
                        .foregroundStyle(amount > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()

            ProportionBar(usage: row.usage)
        }
        .help(Self.rowTooltip(row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.rowTooltip(row).replacingOccurrences(of: "\n", with: ", ")))
    }

    /// Exact figures, plus the Model's full name — the column truncates it and
    /// `claude-haiku-4-5-20251001` needs 172pt against the ~135pt available.
    ///
    /// A kind with no figure prints a dash rather than a zero. Codex reports no
    /// cache-write field at all, so "Cache write 0" would assert a measurement
    /// nobody made; CONTEXT.md calls that absence structural.
    private static func rowTooltip(_ row: TokenOdometerModel.ModelTokens) -> String {
        let figures = TokenKind.allCases.map { kind -> String in
            let amount = row.usage.amount(of: kind)
            return "\(kind.name) \(amount > 0 ? amount.formatted() : "—")"
        }
        return ([row.model.displayName] + figures).joined(separator: "\n")
    }
}

/// Measures the table so the scroll view can be exactly as tall as its content
/// up to the cap, instead of claiming every point offered to it.
private struct TableHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension TokenKind {
    /// The column header's label. The full name rides in the header tooltip,
    /// which is what makes `C·W` discoverable.
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
    ///
    /// Each hue is given twice. These are a colour *key* read against text, not
    /// a brand tint, and the dark-mode values — chosen first, since that is
    /// where this app mostly lives — wash out against a white popover. The
    /// light variants are the same hues darkened to hold their contrast.
    var color: Color {
        switch self {
        case .directInput: Self.adaptive(light: (0.13, 0.42, 0.78), dark: (0.29, 0.60, 0.94))
        case .output: Self.adaptive(light: (0.09, 0.47, 0.35), dark: (0.22, 0.68, 0.53))
        case .cacheWrite: Self.adaptive(light: (0.62, 0.42, 0.06), dark: (0.85, 0.62, 0.22))
        case .cacheRead: Self.adaptive(light: (0.40, 0.36, 0.62), dark: (0.56, 0.52, 0.75))
        }
    }

    private static func adaptive(
        light: (red: Double, green: Double, blue: Double),
        dark: (red: Double, green: Double, blue: Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let variant = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: variant.red, green: variant.green, blue: variant.blue, alpha: 1)
        })
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
                    let amount = usage.amount(of: kind)
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
        // A kind that is present but tiny still gets a visible sliver. Letting
        // it round to nothing would draw it exactly like a kind that is absent,
        // and telling those two apart is the whole reason this bar is here.
        return max(total * CGFloat(amount) / CGFloat(usage.totalTokens), 1.5)
    }
}
