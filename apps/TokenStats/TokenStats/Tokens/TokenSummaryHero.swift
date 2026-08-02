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
        pricingDate: Date = Date(),
        locale: Locale
    ) -> TokenSummaryPresentation {
        let localizer = AppLocalizer(locale: locale)
        let rangeSentenceForm = range.localizedSentenceForm(using: localizer)
        guard hasLoaded else {
            return TokenSummaryPresentation(
                value: "—",
                label: localizer.localized(
                    LocalizedStringResource.tokensSummaryReadingLabel(rangeSentenceForm)
                ),
                help: localizer.localized(
                    LocalizedStringResource.tokensSummaryReadingHelp(rangeSentenceForm)
                ),
                accessibilityLabel: localizer.localized(
                    LocalizedStringResource.tokensSummaryReadingAccessibility(rangeSentenceForm)
                ),
                numericValue: nil
            )
        }

        var total = TokenUsage()
        for agent in perAgent { total.add(agent.usage) }
        let usage = total.responseCount > 0 ? total : nil

        switch metric {
        case .billingTokens:
            return billingPresentation(usage: usage, range: range, localizer: localizer)
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
                localizer: localizer
            )
        }
    }

    private static func billingPresentation(
        usage: TokenUsage?,
        range: TokenRange,
        localizer: AppLocalizer
    ) -> TokenSummaryPresentation {
        let rangeHeadingForm = range.localizedHeadingForm(using: localizer)
        let rangeSentenceForm = range.localizedSentenceForm(using: localizer)
        let label = localizer.localized(
            LocalizedStringResource.tokensSummaryBillingLabel(rangeHeadingForm)
        )
        guard let usage else {
            return TokenSummaryPresentation(
                value: "—",
                label: label,
                help: localizer.localized(
                    LocalizedStringResource.tokensSummaryBillingEmptyHelp(rangeSentenceForm)
                ),
                accessibilityLabel: localizer.localized(
                    LocalizedStringResource.tokensSummaryBillingEmptyAccessibility(rangeSentenceForm)
                ),
                numericValue: nil
            )
        }

        let count = usage.billingTokens
        // The visible summary shares the same locale-aware compact notation as
        // every Token table value. Foundation keeps values below the locale's
        // compact threshold exact; help and accessibility retain the full count.
        let displayedCount = TokenUsage.compact(count, locale: localizer.locale)
        let directInput = usage.inputTokens.formatted(.number.locale(localizer.locale))
        let cacheWrite = usage.cacheCreationTokens.formatted(.number.locale(localizer.locale))
        let output = usage.outputTokens.formatted(.number.locale(localizer.locale))
        let cacheRead = usage.cacheReadTokens.formatted(.number.locale(localizer.locale))
        return TokenSummaryPresentation(
            value: displayedCount,
            label: label,
            help: localizer.localized(
                LocalizedStringResource.tokensSummaryBillingHelp(count, directInput, cacheWrite, output, cacheRead)
            ),
            accessibilityLabel: localizer.localized(
                LocalizedStringResource.tokensSummaryBillingAccessibility(count, rangeSentenceForm)
            ),
            numericValue: Double(count)
        )
    }

    private static func apiEquivalentPresentation(
        usage: TokenUsage?,
        estimate: ApiCostEstimate,
        range: TokenRange,
        localizer: AppLocalizer
    ) -> TokenSummaryPresentation {
        let rangeHeadingForm = range.localizedHeadingForm(using: localizer)
        let rangeSentenceForm = range.localizedSentenceForm(using: localizer)
        let label = localizer.localized(
            LocalizedStringResource.tokensSummaryApiEquivalentLabel(rangeHeadingForm)
        )
        guard usage != nil else {
            return TokenSummaryPresentation(
                value: "—",
                label: label,
                help: localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentEmptyHelp(rangeSentenceForm)
                ),
                accessibilityLabel: localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentEmptyAccessibility(rangeSentenceForm)
                ),
                numericValue: nil
            )
        }

        let reviewed = reviewedDate(locale: localizer.locale)
        let help: String
        if estimate.isPartial {
            let models = estimate.unpricedModels
                .map { $0.localizedDescription(using: localizer) }
                .formatted(
                    .list(type: .and, width: .standard)
                        .locale(localizer.locale)
                )
            help = localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentPartialHelp(
                    estimate.unpricedTokens,
                    reviewed,
                    models
                )
            )
        } else {
            help = localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentHelp(reviewed)
            )
        }

        guard estimate.isAvailable else {
            return TokenSummaryPresentation(
                value: "—",
                label: label,
                help: help,
                accessibilityLabel: localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentUnavailableAccessibility
                ),
                numericValue: nil
            )
        }

        let exactCost = estimate.formattedCost(locale: localizer.locale)
        let displayedCost = compactCurrency(
            estimate.roundedCostUSD,
            exact: exactCost,
            locale: localizer.locale
        )
        return TokenSummaryPresentation(
            value: displayedCost,
            label: label,
            help: localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentExactHelp(exactCost, help)
            ),
            accessibilityLabel: localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentAccessibility(
                    exactCost,
                    rangeSentenceForm
                )
            ),
            numericValue: NSDecimalNumber(decimal: estimate.roundedCostUSD).doubleValue
        )
    }

    /// Currency remains exact and region-aware. The view may scale an unusually
    /// large value, but it never replaces ISO currency semantics with a
    /// hand-authored suffix that would be wrong in some locales.
    private static func compactCurrency(_ amount: Decimal, exact: String, locale: Locale) -> String {
        _ = amount
        _ = locale
        return exact
    }

    static func reviewedDate(
        locale: Locale,
        timeZone: TimeZone = .current
    ) -> String {
        let reviewed = ApiPricingCatalog.lastReviewed
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: reviewed.year,
            month: reviewed.month,
            day: reviewed.day
        )) ?? Date(timeIntervalSince1970: 0)
        var format = Date.FormatStyle()
            .year()
            .month()
            .day()
            .locale(locale)
        // `lastReviewed` is a civil date, not an instant. Constructing and
        // rendering it in the same zone prevents a west/east-zone conversion
        // from moving the displayed review date to an adjacent day.
        format.timeZone = timeZone
        return date.formatted(format)
    }
}

extension TokenRange {
    /// Contextual range spelling for headings. It deliberately has its own
    /// catalog entries instead of reusing the picker title inside other copy.
    func localizedHeadingForm(using localizer: AppLocalizer) -> String {
        let resource: LocalizedStringResource = switch self {
        case .today:
            .tokensRangeTodayHeadingForm
        case .sevenDays:
            .tokensRangeSevenDaysHeadingForm
        case .thirtyDays:
            .tokensRangeThirtyDaysHeadingForm
        }
        return localizer.localized(resource)
    }

    /// Contextual range spelling for insertion into a sentence. English uses
    /// lowercase "today" here while the standalone picker title remains
    /// "Today"; other languages can provide their own grammatical form.
    func localizedSentenceForm(using localizer: AppLocalizer) -> String {
        let resource: LocalizedStringResource = switch self {
        case .today:
            .tokensRangeTodaySentenceForm
        case .sevenDays:
            .tokensRangeSevenDaysSentenceForm
        case .thirtyDays:
            .tokensRangeThirtyDaysSentenceForm
        }
        return localizer.localized(resource)
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

    @Environment(\.locale) private var locale

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
            hasLoaded: hasLoaded,
            locale: locale
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
                .minimumScaleFactor(0.6)
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
