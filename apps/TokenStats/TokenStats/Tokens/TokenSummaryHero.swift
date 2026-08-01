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
    /// Identifies the semantic unit behind `numericValue`. A changed identity
    /// replaces the value with a short crossfade instead of rolling digits
    /// between unrelated units such as tokens, USD, and CNY.
    let transitionIdentity: String

    static func make(
        perAgent: [TokenOdometerModel.AgentTokens],
        metric: TokenSummaryMetric,
        range: TokenRange,
        hasLoaded: Bool,
        pricingDate: Date = Date(),
        currencyContext: CurrencyDisplayContext = .usd
    ) -> TokenSummaryPresentation {
        let transitionIdentity = transitionIdentity(
            metric: metric,
            currencyContext: currencyContext
        )
        guard hasLoaded else {
            return TokenSummaryPresentation(
                value: "—",
                label: "Reading \(range.label.lowercased())…",
                help: "Reading token usage for \(range.label).",
                accessibilityLabel: "Reading token usage for \(range.label)",
                numericValue: nil,
                transitionIdentity: transitionIdentity
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
                range: range,
                currencyContext: currencyContext
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
                numericValue: nil,
                transitionIdentity: TokenSummaryMetric.billingTokens.rawValue
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
            numericValue: Double(count),
            transitionIdentity: TokenSummaryMetric.billingTokens.rawValue
        )
    }

    private static func apiEquivalentPresentation(
        usage: TokenUsage?,
        estimate: ApiCostEstimate,
        range: TokenRange,
        currencyContext: CurrencyDisplayContext
    ) -> TokenSummaryPresentation {
        let label = apiEquivalentLabel(
            range: range,
            currencyContext: currencyContext
        )
        let transitionIdentity = transitionIdentity(
            metric: .apiEquivalent,
            currencyContext: currencyContext
        )
        guard usage != nil else {
            return TokenSummaryPresentation(
                value: "—",
                label: label,
                help: "No API-equivalent usage for \(range.label).",
                accessibilityLabel: "No API-equivalent usage for \(range.label)",
                numericValue: nil,
                transitionIdentity: transitionIdentity
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
            + "The exact USD aggregate is converted before the displayed total is "
            + "rounded upward once to the target currency's minor unit. Claude cache "
            + "writes without TTL detail use the default 5-minute rate. "
            + "Prices reviewed \(reviewed)." + unpriced
        let currencyDisclosure = currencyDisclosure(currencyContext)

        guard estimate.isAvailable else {
            return TokenSummaryPresentation(
                value: "—",
                label: label,
                help: help + " " + currencyDisclosure,
                accessibilityLabel: "API-equivalent usage unavailable because the "
                    + "transcript Model is unknown. " + currencyDisclosure + unpriced,
                numericValue: nil,
                transitionIdentity: transitionIdentity
            )
        }

        // Convert the exact aggregate. Rounding the USD amount first and then
        // converting would compound presentation rounding in the local value.
        let amount = currencyContext.amount(forUSD: estimate.costUSD)
        // Compact notation is only a width escape hatch for seven-figure
        // totals. Ordinary values keep the currency's full minor-unit detail.
        let shouldCompact = amount.roundedValue >= 1_000_000
        let fullLocalCost = amount.currencyCode == .usd
            ? estimate.formattedCostUSD
            : amount.formatted(compact: false)
        let displayedCost = shouldCompact
            ? compactDisplay(amount)
            : fullLocalCost
        let unpricedAccessibility = estimate.isPartial
            ? " Unpriced models: \(estimate.unpricedModels.joined(separator: ", ")), "
                + "\(estimate.unpricedTokens.formatted()) tokens."
            : ""
        return TokenSummaryPresentation(
            value: displayedCost,
            label: label,
            help: "Displayed estimate \(fullLocalCost). Original USD estimate "
                + "\(estimate.formattedCostUSD). \(currencyDisclosure) " + help,
            accessibilityLabel: "\(fullLocalCost) estimated API-equivalent usage for "
                + "\(range.label). Original USD estimate \(estimate.formattedCostUSD). "
                + currencyDisclosure + unpricedAccessibility,
            numericValue: amount.numericValue,
            transitionIdentity: transitionIdentity
        )
    }

    private static func apiEquivalentLabel(
        range: TokenRange,
        currencyContext: CurrencyDisplayContext
    ) -> String {
        let code = currencyContext.currencyCode.rawValue
        let currency = currencyContext.isFallback ? "\(code) fallback" : code
        return "API-equivalent · \(currency) · \(range.label)"
    }

    private static func compactDisplay(_ amount: CurrencyDisplayAmount) -> String {
        let formatted = amount.formatted(compact: true)
        guard amount.currencyCode == .usd else { return formatted }
        // Foundation's POSIX currency style inserts a non-breaking space,
        // unlike the pre-existing compact USD hero. Preserve the established
        // `$5M` spelling for the base/fallback currency.
        return formatted.replacingOccurrences(of: "\u{00A0}", with: "")
    }

    private static func transitionIdentity(
        metric: TokenSummaryMetric,
        currencyContext: CurrencyDisplayContext
    ) -> String {
        guard metric == .apiEquivalent else { return metric.rawValue }
        return [
            metric.rawValue,
            currencyContext.requestedCode.rawValue,
            currencyContext.currencyCode.rawValue,
            currencyContext.isFallback ? "fallback" : "converted",
        ].joined(separator: ":")
    }

    private static func currencyDisclosure(
        _ context: CurrencyDisplayContext
    ) -> String {
        let effectiveCode = context.currencyCode.rawValue
        let requestedCode = context.requestedCode.rawValue

        if context.isFallback {
            var parts = [
                "No usable \(requestedCode) exchange rate was available.",
                "No FX conversion was applied; showing the original USD estimate.",
            ]
            if let fetchedAt = context.fetchedAt {
                parts.append("Last rate table fetched: \(ISO8601DateFormatter().string(from: fetchedAt)).")
            }
            return parts.joined(separator: " ")
        }

        var parts = [
            "Exchange rate: 1 USD = \(formatRate(context.rate)) \(effectiveCode).",
        ]

        if effectiveCode == CurrencyCode.usd.rawValue {
            parts.append("USD is the pricing currency; no FX rate date or fetch time applies.")
        } else {
            if let rateDate = context.rateDate {
                parts.append("Rate date: \(formatRateDate(rateDate)).")
            } else {
                parts.append("Rate date unavailable.")
            }
            if let fetchedAt = context.fetchedAt {
                parts.append("Fetched: \(ISO8601DateFormatter().string(from: fetchedAt)).")
            } else {
                parts.append("Fetch time unavailable.")
            }
            parts.append(context.isStale ? "Rate status: stale cached rate." : "Rate status: current.")
        }

        return parts.joined(separator: " ")
    }

    private static func formatRateDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatRate(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSDecimalNumber(decimal: rate))
            ?? NSDecimalNumber(decimal: rate).stringValue
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
    let currencyContext: CurrencyDisplayContext

    init(
        perAgent: [TokenOdometerModel.AgentTokens],
        metric: TokenSummaryMetric,
        range: TokenRange,
        hasLoaded: Bool,
        currencyContext: CurrencyDisplayContext = .usd
    ) {
        self.perAgent = perAgent
        self.metric = metric
        self.range = range
        self.hasLoaded = hasLoaded
        self.currencyContext = currencyContext
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `nil` until this view has settled its first presentation. That first
    /// value appears immediately, matching v1's conditionally inserted hero.
    @State private var presentedIdentity: String?
    @State private var hasPresentedNumber = false

    private var presentation: TokenSummaryPresentation {
        .make(
            perAgent: perAgent,
            metric: metric,
            range: range,
            hasLoaded: hasLoaded,
            currencyContext: currencyContext
        )
    }

    private var shouldAnimate: Bool {
        !reduceMotion
            && hasPresentedNumber
            && presentedIdentity == presentation.transitionIdentity
            && presentation.numericValue != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                Text(presentation.value)
                    // SwiftUI owns the same-unit per-digit motion. Changing
                    // metric or currency replaces this child instead.
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
                    .id(presentation.transitionIdentity)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .opacity.combined(with: .scale(scale: 0.98))
                    )
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.25),
                value: presentation.transitionIdentity
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
            presentedIdentity = presentation.transitionIdentity
            hasPresentedNumber = presentation.numericValue != nil
        }
        .onChange(of: presentation.transitionIdentity) { _, newIdentity in
            // Units changed, so settle rather than implying a numeric delta.
            presentedIdentity = newIdentity
            hasPresentedNumber = presentation.numericValue != nil
        }
        .onChange(of: presentation.numericValue) { _, newValue in
            if newValue != nil { hasPresentedNumber = true }
        }
    }
}
