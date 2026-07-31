//
//  TokenSummaryHero.swift
//  TokenStats
//
//  The objective summary at the top of the Tokens tab. It can present Billing
//  tokens or an API-equivalent list-price estimate without changing the raw
//  Token Odometer or the Token Kind table projection.
//

import SwiftUI

@MainActor
struct TokenSummaryPresentation: Equatable {
    let value: String
    let label: String
    let help: String
    let accessibilityLabel: String
    /// The semantic number behind `value`, used only by SwiftUI's native
    /// numeric transition. Nil means the reading is unavailable.
    let numericValue: Double?

    static func make(
        perAgent: [TokenOdometerModel.AgentTokens],
        metric: TokenSummaryMetric,
        range: TokenRange,
        hasLoaded: Bool,
        pricingDate: Date = Date()
    ) -> TokenSummaryPresentation {
        guard hasLoaded else {
            return TokenSummaryPresentation(
                value: "—",
                label: "Reading \(range.label.lowercased())…",
                help: "Reading token usage for \(range.label).",
                accessibilityLabel: "Reading token usage for \(range.label)",
                numericValue: nil
            )
        }

        var total = TokenUsage()
        for agent in perAgent { total.add(agent.usage) }
        let usage = total.responseCount > 0 ? total : nil

        switch metric {
        case .billingTokens:
            return billingPresentation(usage: usage, range: range)
        case .apiEquivalent:
            let rows = perAgent.flatMap { agent in
                agent.byModel.map { row in
                    (agent: agent.id, model: row.model, usage: row.usage)
                }
            }
            let estimate = ApiPricingCatalog.estimate(
                rows,
                totalUsage: usage,
                on: pricingDate
            )
            return apiEquivalentPresentation(
                usage: usage,
                estimate: estimate,
                range: range
            )
        }
    }

    private static func billingPresentation(
        usage: TokenUsage?,
        range: TokenRange
    ) -> TokenSummaryPresentation {
        guard let usage else {
            return TokenSummaryPresentation(
                value: "—",
                label: "billing tokens · \(range.label)",
                help: "No billing token usage for \(range.label).",
                accessibilityLabel: "No billing token usage for \(range.label)",
                numericValue: nil
            )
        }

        let count = usage.billingTokens
        // The popover gives the hero 300pt. A grouped ten-digit count no longer
        // fits the v1 42pt face and SwiftUI's minimumScaleFactor used to shrink
        // that range while shorter ranges stayed full-size. Compact only beyond
        // the largest exact value that fits, and keep the exact count in help
        // and accessibility text.
        let displayedCount = count >= 1_000_000_000
            ? TokenUsage.compact(count)
            : count.formatted()
        let breakdown = "Direct input \(usage.inputTokens.formatted()) · "
            + "Cache write \(usage.cacheCreationTokens.formatted()) · "
            + "Output \(usage.outputTokens.formatted()) · "
            + "Cache read \(usage.cacheReadTokens.formatted())"
        return TokenSummaryPresentation(
            value: displayedCount,
            label: "billing tokens · \(range.label)",
            help: "\(count.formatted()) billing tokens. \(breakdown). "
                + "Billing tokens include direct input, cache writes, "
                + "and output; cache reads remain visible in the table but are excluded "
                + "from this total. Token Kind filters do not change this objective summary.",
            accessibilityLabel: "\(count.formatted()) billing tokens for \(range.label); "
                + "cache reads excluded",
            numericValue: Double(count)
        )
    }

    private static func apiEquivalentPresentation(
        usage: TokenUsage?,
        estimate: ApiCostEstimate,
        range: TokenRange
    ) -> TokenSummaryPresentation {
        guard usage != nil else {
            return TokenSummaryPresentation(
                value: "—",
                label: "API-equivalent · \(range.label)",
                help: "No API-equivalent usage for \(range.label).",
                accessibilityLabel: "No API-equivalent usage for \(range.label)",
                numericValue: nil
            )
        }

        let unpriced = estimate.isPartial
            ? " Unpriced: \(estimate.unpricedModels.joined(separator: ", ")) "
                + "(\(estimate.unpricedTokens.formatted()) tokens)."
            : ""
        let reviewed = "\(ApiPricingCatalog.lastReviewed.year)-"
            + String(format: "%02d", ApiPricingCatalog.lastReviewed.month)
            + "-" + String(format: "%02d", ApiPricingCatalog.lastReviewed.day)
        let help = "Standard API-equivalent estimate by recorded Model; includes all "
            + "four Token Kinds at list rates regardless of the display filters. "
            + "The final total is rounded upward to the nearest cent. Claude cache "
            + "writes without TTL detail use the default 5-minute rate. "
            + "Prices reviewed \(reviewed)." + unpriced

        guard estimate.isAvailable else {
            return TokenSummaryPresentation(
                value: "—",
                label: "API-equivalent · \(range.label)",
                help: help,
                accessibilityLabel: "API-equivalent usage unavailable because the "
                    + "transcript Model is unknown",
                numericValue: nil
            )
        }

        let displayedCost = compactCurrency(
            estimate.roundedCostUSD,
            exact: estimate.formattedCost
        )
        return TokenSummaryPresentation(
            value: displayedCost,
            label: "API-equivalent · \(range.label)",
            help: "Exact estimate \(estimate.formattedCost). " + help,
            accessibilityLabel: "\(estimate.formattedCost) estimated API-equivalent "
                + "usage for \(range.label)",
            numericValue: NSDecimalNumber(decimal: estimate.roundedCostUSD).doubleValue
        )
    }

    /// Keep the API summary in the same fixed 42pt slot if an unusually large
    /// local corpus crosses seven figures. Ordinary estimates remain exact.
    private static func compactCurrency(_ amount: Decimal, exact: String) -> String {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M")]
        guard let (unit, suffix) = units.first(where: { value >= $0.0 }) else {
            return exact
        }
        let scaled = value / unit
        let text = scaled < 9.95
            ? String(format: "%.1f", scaled)
            : String(format: "%.0f", scaled)
        return "$\(text)\(suffix)"
    }
}

struct TokenSummaryHero: View {
    /// Stable layout contract for the value, label, and the space between them.
    /// The table below remains content-sized; only this hero is isolated from
    /// popover height changes.
    static let valueFontSize: CGFloat = 42
    static let valueSlotHeight: CGFloat = 52
    static let fixedHeight: CGFloat = 76

    let perAgent: [TokenOdometerModel.AgentTokens]
    let metric: TokenSummaryMetric
    let range: TokenRange
    let hasLoaded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `nil` until this view has settled its first presentation. That first
    /// value appears immediately, matching v1's conditionally inserted hero.
    @State private var presentedMetric: TokenSummaryMetric?
    @State private var hasPresentedNumber = false

    private var presentation: TokenSummaryPresentation {
        .make(
            perAgent: perAgent,
            metric: metric,
            range: range,
            hasLoaded: hasLoaded
        )
    }

    private var shouldAnimate: Bool {
        !reduceMotion
            && hasPresentedNumber
            && presentedMetric == metric
            && presentation.numericValue != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.value)
                // This is the v1 macOS animation: SwiftUI owns the per-digit
                // motion and its platform feel. Windows' hand-drawn rolling
                // control is deliberately not shared.
                .font(.system(size: Self.valueFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(
                    .numericText(value: presentation.numericValue ?? 0)
                )
                .animation(
                    shouldAnimate ? .snappy(duration: 0.6) : nil,
                    value: presentation.numericValue
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: Self.valueSlotHeight,
                    maxHeight: Self.valueSlotHeight,
                    alignment: .bottomLeading
                )
            Text(presentation.label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: Self.fixedHeight,
            maxHeight: Self.fixedHeight,
            alignment: .topLeading
        )
        .help(presentation.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .onAppear {
            presentedMetric = metric
            hasPresentedNumber = presentation.numericValue != nil
        }
        .onChange(of: metric) { _, newMetric in
            // Units changed, so settle rather than implying a numeric delta.
            presentedMetric = newMetric
            hasPresentedNumber = presentation.numericValue != nil
        }
        .onChange(of: presentation.numericValue) { _, newValue in
            if newValue != nil { hasPresentedNumber = true }
        }
    }
}
