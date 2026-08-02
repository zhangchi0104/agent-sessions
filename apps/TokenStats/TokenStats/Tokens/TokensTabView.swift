//
//  TokensTabView.swift
//  TokenStats
//
//  The popover's Tokens tab: the Token Odometer for the selected range, as a
//  table grouped by Coding Agent then Model, four Token Kinds to a row with a
//  proportion bar tucked beneath. An objective Billing/API-equivalent summary
//  leads the tab; filtered per-agent subtotals remain a separate projection.
//
//  The colour key rides in the column header rather than a legend block: a
//  spelled-out legend measures 298pt against the 298pt this popover has, which
//  would make the wording of four labels a layout constraint. Full names live
//  in the header tooltips and in CONTEXT.md.
//

import SwiftUI
import AppKit

nonisolated struct TokenTableHeadingPresentation: Equatable, Sendable {
    let visual: String
    let help: String
    let accessibilityLabel: String

    static func make(
        rangeHeading: String,
        selectedTotal: Int?,
        localizer: AppLocalizer
    ) -> TokenTableHeadingPresentation {
        guard let selectedTotal else {
            return TokenTableHeadingPresentation(
                visual: rangeHeading,
                help: rangeHeading,
                accessibilityLabel: rangeHeading
            )
        }

        let compact = TokenUsage.compact(selectedTotal, locale: localizer.locale)
        let exact = selectedTotal.formatted(.number.locale(localizer.locale))
        let visual = localizer.localized(
            LocalizedStringResource.tokensTableHeadingSelected(rangeHeading, compact)
        )
        let exactText = localizer.localized(
            LocalizedStringResource.tokensTableHeadingSelected(rangeHeading, exact)
        )
        return TokenTableHeadingPresentation(
            visual: visual,
            help: exactText,
            accessibilityLabel: exactText
        )
    }
}

struct TokensTabView: View {
    let odometer: TokenOdometerModel
    @Bindable var appearance: AppearanceSettings

    /// How tall the table is allowed to grow before it scrolls instead. The
    /// popover has no height of its own — it is exactly as tall as its content
    /// — so without a ceiling a user with many Models gets a window taller
    /// than the screen. 11 Model rows measured ~539pt in the layout prototype.
    // The summary hero and its selector add about 100pt over the original
    // table-only layout. Lower the table cap by the same amount so the popover
    // still fits a compact Mac display; additional Model rows scroll here.
    private static let tableHeightCap: CGFloat = 360

    @State private var tableHeight: CGFloat = 0
    @Environment(\.locale) private var locale

    private var localizer: AppLocalizer { AppLocalizer(locale: locale) }

    /// Dimmed while a scan is in flight — either the first of this appearance,
    /// or a longer range the user switched to — so the tab shows a cue rather
    /// than a bare column header or a table that empties for several seconds.
    private var isScanning: Bool { odometer.pendingRange != nil || odometer.hasLoaded == false }

    /// The Odometer continues to retain every agent's raw reading so changing
    /// this presentation preference never starts or cancels a transcript scan.
    /// This projection is the single filtered list shared by the hero, heading,
    /// and table, keeping every Tokens total on the same agent set.
    private var visibleAgents: [TokenOdometerModel.AgentTokens] {
        TokenAgentProjection.visible(odometer.perAgent,
                                    inOrder: appearance.tokensDisplayOrder)
    }

    private var visibleUsage: TokenUsage? {
        TokenAgentProjection.usage(of: visibleAgents)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryMetricPicker
            TokenSummaryHero(
                perAgent: visibleAgents,
                metric: appearance.tokenSummaryMetric,
                range: odometer.displayedRange,
                hasLoaded: odometer.hasLoaded
            )
            .opacity(isScanning ? 0.6 : 1)
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

    private var summaryMetricPicker: some View {
        Picker(
            LocalizedStringResource.tokensSummaryPickerTitle,
            selection: Binding(
            get: { appearance.tokenSummaryMetric },
            set: { metric in
                // Switching between two different units must settle
                // immediately. Value and range changes keep the v1 macOS
                // numeric transition; this presentation switch does not.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    appearance.tokenSummaryMetric = metric
                }
            }
        )) {
            ForEach(TokenSummaryMetric.allCases) { metric in
                Text(metric.title).tag(metric)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(
            LocalizedStringResource.tokensSummaryPickerAccessibility
        )
    }

    private var rangePicker: some View {
        Picker(
            LocalizedStringResource.tokensRangePickerTitle,
            selection: Binding(
            get: { odometer.selectedRange },
            set: { range in
                appearance.selectedTokenRange = range
                odometer.select(range)
            }
        )) {
            ForEach(TokenRange.allCases, id: \.self) { range in
                Text(range.title).tag(range)
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
        .accessibilityLabel(
            LocalizedStringResource.tokensRangePickerAccessibility
        )
    }

    /// The heading names the range the rows below actually describe — never the
    /// pending one; switching to 30 days must not relabel today's numbers while
    /// the scan runs. The cue sits beside it rather than over the table, so it
    /// never lands on the column header, and it names the range being *read*,
    /// which is the one thing allowed to run ahead of the data.
    private var headingRow: some View {
        let heading = tableHeadingPresentation
        return HStack(spacing: 6) {
            Text(heading.visual)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.4)
                .help(heading.help)
                .accessibilityLabel(Text(heading.accessibilityLabel))
            Spacer(minLength: 8)
            if isScanning {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(readingRangeText)
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.secondary)
        .frame(height: 14)
    }

    private var tableHeadingPresentation: TokenTableHeadingPresentation {
        let rangeHeading = odometer.displayedRange.localizedHeadingForm(using: localizer)
        let selectedTotal = visibleUsage?.selectedTotal(appearance.selectedTokenKinds)
        return TokenTableHeadingPresentation.make(
            rangeHeading: rangeHeading,
            selectedTotal: selectedTotal,
            localizer: localizer
        )
    }

    private var readingRangeText: String {
        let rangeSentenceForm = (odometer.pendingRange ?? odometer.selectedRange)
            .localizedSentenceForm(using: localizer)
        return localizer.localized(
            LocalizedStringResource.tokensTableReadingRange(rangeSentenceForm)
        )
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
            ForEach(visibleAgents, id: \.id) { agent in
                agentGroup(agent)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(
                LocalizedStringResource.tokensTableColumnModel
            )
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(TokenKind.allCases, id: \.self) { kind in
                Toggle(isOn: tokenKindBinding(kind)) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(kind.color)
                            .frame(width: 6, height: 6)
                        Text(kind.abbreviation)
                    }
                    .foregroundStyle(kind.color)
                    .frame(width: 42, alignment: .trailing)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .opacity(appearance.selectedTokenKinds.contains(kind) ? 1 : 0.38)
                .help(tokenKindHelp(kind))
                .accessibilityLabel(tokenKindAccessibilityLabel(kind))
            }
        }
        .font(.system(size: 9.5, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
    }

    private func tokenKindBinding(_ kind: TokenKind) -> Binding<Bool> {
        Binding(
            get: { appearance.selectedTokenKinds.contains(kind) },
            set: { isSelected in
                if !appearance.setTokenKind(kind, isSelected: isSelected) {
                    NSSound.beep()
                }
            }
        )
    }

    private func tokenKindHelp(_ kind: TokenKind) -> String {
        TokenKindPresentation.help(
            for: kind,
            isSelected: appearance.selectedTokenKinds.contains(kind),
            using: localizer
        )
    }

    private func tokenKindAccessibilityLabel(_ kind: TokenKind) -> String {
        TokenKindPresentation.accessibilityLabel(for: kind, using: localizer)
    }

    @ViewBuilder private func agentGroup(_ agent: TokenOdometerModel.AgentTokens) -> some View {
        let selectedTotal = agent.usage.selectedTotal(appearance.selectedTokenKinds)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(agent.label.uppercased())
                Spacer()
                if agent.byModel.isEmpty == false {
                    Text(TokenUsage.compact(selectedTotal, locale: locale))
                        .monospacedDigit()
                        .help(agentSelectedTotalHelp(agent, selectedTotal: selectedTotal))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(agent.byModel.isEmpty
                                ? Text(agent.label)
                                : Text(agentSelectedTotalAccessibilityLabel(
                                    agent,
                                    selectedTotal: selectedTotal
                                )))

            if agent.byModel.isEmpty {
                // An ordinary state, not an error: an agent with nothing in the
                // selected range says so rather than leaving a bare heading.
                Text(
                    LocalizedStringResource.tokensTableEmptyRange
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedRows(agent.byModel), id: \.model) { row in
                    modelRow(row)
                }
            }
        }
    }

    private func agentSelectedTotalHelp(
        _ agent: TokenOdometerModel.AgentTokens,
        selectedTotal: Int
    ) -> String {
        let total = agent.usage.totalTokens.formatted(.number.locale(locale))
        return localizer.localized(
            LocalizedStringResource.tokensAgentSelectedTotalHelp(selectedTotal, total)
        )
    }

    private func agentSelectedTotalAccessibilityLabel(
        _ agent: TokenOdometerModel.AgentTokens,
        selectedTotal: Int
    ) -> String {
        return localizer.localized(
            LocalizedStringResource.tokensAgentSelectedTotalAccessibility(selectedTotal, agent.label)
        )
    }

    private func sortedRows(
        _ rows: [TokenOdometerModel.ModelTokens]
    ) -> [TokenOdometerModel.ModelTokens] {
        rows.sorted { left, right in
            let leftTotal = left.usage.selectedTotal(appearance.selectedTokenKinds)
            let rightTotal = right.usage.selectedTotal(appearance.selectedTokenKinds)
            if leftTotal != rightTotal { return leftTotal > rightTotal }
            return left.model < right.model
        }
    }

    private func modelRow(_ row: TokenOdometerModel.ModelTokens) -> some View {
        let selectedTotal = row.usage.selectedTotal(appearance.selectedTokenKinds)
        let modelName = row.model.localizedDisplayName(using: localizer)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(modelName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                ForEach(TokenKind.allCases, id: \.self) { kind in
                    let amount = row.usage.amount(of: kind)
                    let isSelected = appearance.selectedTokenKinds.contains(kind)
                    Text(TokenValueFormatting.cell(
                        amount: amount,
                        selectedTotal: selectedTotal,
                        isSelected: isSelected,
                        mode: appearance.tokenValueDisplay,
                        locale: locale
                    ))
                        // Only the two-line value-plus-percentage cell needs the
                        // smaller face. Model names and disabled raw values keep
                        // the table's normal 12pt reading size.
                        .font(.system(
                            size: isSelected && appearance.tokenValueDisplay == .valueAndPercentage
                                ? 9.5 : 12
                        ))
                        .frame(width: 42, alignment: .trailing)
                        .foregroundStyle(amount > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .opacity(isSelected ? 1 : 0.32)
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()

            ProportionBar(usage: row.usage, selection: appearance.selectedTokenKinds)
        }
        .help(rowTooltip(row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(rowTooltip(row).replacingOccurrences(of: "\n", with: ", ")))
    }

    /// Exact figures, plus the Model's full name — the column truncates it and
    /// `claude-haiku-4-5-20251001` needs 172pt against the ~135pt available.
    ///
    /// A kind with no figure prints a dash rather than a zero. Codex reports no
    /// cache-write field at all, so "Cache write 0" would assert a measurement
    /// nobody made; CONTEXT.md calls that absence structural.
    private func rowTooltip(_ row: TokenOdometerModel.ModelTokens) -> String {
        let selectedTotal = row.usage.selectedTotal(appearance.selectedTokenKinds)
        let modelName = row.model.localizedDisplayName(using: localizer)
        let figures = TokenKind.allCases.map { kind -> String in
            let amount = row.usage.amount(of: kind)
            guard amount > 0 else {
                return TokenKindPresentation.unavailableRow(
                    for: kind,
                    using: localizer
                )
            }
            let formattedAmount = amount.formatted(.number.locale(locale))
            if appearance.selectedTokenKinds.contains(kind) {
                let percentage = TokenValueFormatting.compositionPercentage(
                    amount: amount,
                    total: selectedTotal,
                    locale: locale
                )
                return TokenKindPresentation.selectedRow(
                    for: kind,
                    formattedAmount: formattedAmount,
                    percentage: percentage,
                    using: localizer
                )
            }
            return TokenKindPresentation.excludedRow(
                for: kind,
                formattedAmount: formattedAmount,
                using: localizer
            )
        }
        return ([modelName] + figures).joined(separator: "\n")
    }
}

@MainActor
enum TokenKindPresentation {
    static func help(
        for kind: TokenKind,
        isSelected: Bool,
        using localizer: AppLocalizer
    ) -> String {
        let kindForm = kind.localizedActionForm(using: localizer)
        return localizer.localized(
            isSelected
                ? LocalizedStringResource.tokensKindExcludeHelp(kindForm)
                : LocalizedStringResource.tokensKindIncludeHelp(kindForm)
        )
    }

    static func accessibilityLabel(
        for kind: TokenKind,
        using localizer: AppLocalizer
    ) -> String {
        localizer.localized(
            LocalizedStringResource.tokensKindIncludeAccessibility(
                kind.localizedActionForm(using: localizer)
            )
        )
    }

    static func unavailableRow(
        for kind: TokenKind,
        using localizer: AppLocalizer
    ) -> String {
        localizer.localized(
            LocalizedStringResource.tokensRowKindUnavailable(
                kind.localizedRowPrefix(using: localizer)
            )
        )
    }

    static func selectedRow(
        for kind: TokenKind,
        formattedAmount: String,
        percentage: String,
        using localizer: AppLocalizer
    ) -> String {
        localizer.localized(
            LocalizedStringResource.tokensRowKindSelected(
                kind.localizedRowPrefix(using: localizer),
                formattedAmount,
                percentage
            )
        )
    }

    static func excludedRow(
        for kind: TokenKind,
        formattedAmount: String,
        using localizer: AppLocalizer
    ) -> String {
        localizer.localized(
            LocalizedStringResource.tokensRowKindExcluded(
                kind.localizedRowPrefix(using: localizer),
                formattedAmount
            )
        )
    }
}

private extension TokenKind {
    func localizedActionForm(using localizer: AppLocalizer) -> String {
        let resource: LocalizedStringResource = switch self {
        case .directInput:
            .tokensKindDirectInputActionForm
        case .output:
            .tokensKindOutputActionForm
        case .cacheWrite:
            .tokensKindCacheWriteActionForm
        case .cacheRead:
            .tokensKindCacheReadActionForm
        }
        return localizer.localized(resource)
    }

    func localizedRowPrefix(using localizer: AppLocalizer) -> String {
        let resource: LocalizedStringResource = switch self {
        case .directInput:
            .tokensKindDirectInputRowPrefix
        case .output:
            .tokensKindOutputRowPrefix
        case .cacheWrite:
            .tokensKindCacheWriteRowPrefix
        case .cacheRead:
            .tokensKindCacheReadRowPrefix
        }
        return localizer.localized(resource)
    }
}

/// Pure Tokens-tab projection shared by the view and tests. The Odometer keeps
/// all agent slices; the selected surface order decides which slices take part
/// in the visible table and its objective summaries.
@MainActor
enum TokenAgentProjection {
    static func visible(
        _ agents: [TokenOdometerModel.AgentTokens],
        inOrder order: [CodingAgentID]
    ) -> [TokenOdometerModel.AgentTokens] {
        let byID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        return order.compactMap { byID[$0] }
    }

    static func usage(of agents: [TokenOdometerModel.AgentTokens]) -> TokenUsage? {
        var total = TokenUsage()
        for agent in agents { total.add(agent.usage) }
        return total.responseCount > 0 ? total : nil
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
    var abbreviation: LocalizedStringResource {
        switch self {
        case .directInput:
            LocalizedStringResource.tokensKindDirectInputAbbreviation
        case .output:
            LocalizedStringResource.tokensKindOutputAbbreviation
        case .cacheWrite:
            LocalizedStringResource.tokensKindCacheWriteAbbreviation
        case .cacheRead:
            LocalizedStringResource.tokensKindCacheReadAbbreviation
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
    let selection: Set<TokenKind>

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(TokenKind.allCases.filter(selection.contains), id: \.self) { kind in
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
        let selectedTotal = usage.selectedTotal(selection)
        guard selectedTotal > 0 else { return 0 }
        // A kind that is present but tiny still gets a visible sliver. Letting
        // it round to nothing would draw it exactly like a kind that is absent,
        // and telling those two apart is the whole reason this bar is here.
        return max(total * CGFloat(amount) / CGFloat(selectedTotal), 1.5)
    }
}
