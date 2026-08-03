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
    /// A width-efficient restatement for the secondary label row. The hero
    /// keeps the exact Billing-token count; this preserves the quick compact
    /// reading without making it the primary value.
    let compactValue: String?
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
        currencyContext: CurrencyDisplayContext = .usd,
        locale: Locale
    ) -> TokenSummaryPresentation {
        let localizer = AppLocalizer(locale: locale)
        let rangeSentenceForm = range.localizedSentenceForm(using: localizer)
        let identity = transitionIdentity(metric: metric, currencyContext: currencyContext)
        guard hasLoaded else {
            return TokenSummaryPresentation(
                value: "—",
                compactValue: nil,
                label: localizer.localized(
                    LocalizedStringResource.tokensSummaryReadingLabel(rangeSentenceForm)
                ),
                help: localizer.localized(
                    LocalizedStringResource.tokensSummaryReadingHelp(rangeSentenceForm)
                ),
                accessibilityLabel: localizer.localized(
                    LocalizedStringResource.tokensSummaryReadingAccessibility(rangeSentenceForm)
                ),
                numericValue: nil,
                transitionIdentity: identity
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
                currencyContext: currencyContext,
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
                compactValue: nil,
                label: label,
                help: localizer.localized(
                    LocalizedStringResource.tokensSummaryBillingEmptyHelp(rangeSentenceForm)
                ),
                accessibilityLabel: localizer.localized(
                    LocalizedStringResource.tokensSummaryBillingEmptyAccessibility(rangeSentenceForm)
                ),
                numericValue: nil,
                transitionIdentity: TokenSummaryMetric.billingTokens.rawValue
            )
        }

        let count = usage.billingTokens
        let displayedCount = count.formatted(.number.locale(localizer.locale))
        let compactCandidate = TokenUsage.compact(count, locale: localizer.locale)
        // Use the default compact result only to detect whether this locale has
        // crossed a real unit threshold. Forcing fraction digits before this
        // check can turn an exact value into redundant secondary text.
        let ungroupedCount = count.formatted(
            .number
                .grouping(.never)
                .locale(localizer.locale)
        )
        let shouldShowCompact = compactCandidate != displayedCount && compactCandidate != ungroupedCount
        let compactCount = shouldShowCompact
            ? count.formatted(
                .number
                    .precision(.fractionLength(2))
                    .notation(.compactName)
                    .locale(localizer.locale)
            )
            : nil
        let directInput = usage.inputTokens.formatted(.number.locale(localizer.locale))
        let cacheWrite = usage.cacheCreationTokens.formatted(.number.locale(localizer.locale))
        let output = usage.outputTokens.formatted(.number.locale(localizer.locale))
        let cacheRead = usage.cacheReadTokens.formatted(.number.locale(localizer.locale))
        return TokenSummaryPresentation(
            value: displayedCount,
            compactValue: compactCount,
            label: label,
            help: localizer.localized(
                LocalizedStringResource.tokensSummaryBillingHelp(
                    count,
                    directInput,
                    cacheWrite,
                    output,
                    cacheRead
                )
            ),
            accessibilityLabel: localizer.localized(
                LocalizedStringResource.tokensSummaryBillingAccessibility(count, rangeSentenceForm)
            ),
            numericValue: Double(count),
            transitionIdentity: TokenSummaryMetric.billingTokens.rawValue
        )
    }

    private static func apiEquivalentPresentation(
        usage: TokenUsage?,
        estimate: ApiCostEstimate,
        range: TokenRange,
        currencyContext: CurrencyDisplayContext,
        localizer: AppLocalizer
    ) -> TokenSummaryPresentation {
        let rangeHeadingForm = range.localizedHeadingForm(using: localizer)
        let rangeSentenceForm = range.localizedSentenceForm(using: localizer)
        let currencyLabel = localizedCurrencyLabel(currencyContext, localizer: localizer)
        let label = localizer.localized(
            LocalizedStringResource.tokensSummaryApiEquivalentLabel(
                currencyLabel,
                rangeHeadingForm
            )
        )
        let identity = transitionIdentity(
            metric: .apiEquivalent,
            currencyContext: currencyContext
        )
        guard usage != nil else {
            return TokenSummaryPresentation(
                value: "—",
                compactValue: nil,
                label: label,
                help: localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentEmptyHelp(rangeSentenceForm)
                ),
                accessibilityLabel: localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentEmptyAccessibility(rangeSentenceForm)
                ),
                numericValue: nil,
                transitionIdentity: identity
            )
        }

        let reviewed = reviewedDate(locale: localizer.locale)
        let unpricedModels = localizedUnpricedModels(estimate, localizer: localizer)
        let methodology: String
        if estimate.isPartial {
            methodology = localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentPartialHelp(
                    estimate.unpricedTokens,
                    reviewed,
                    unpricedModels
                )
            )
        } else {
            methodology = localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentHelp(reviewed)
            )
        }
        let disclosure = currencyDisclosure(currencyContext, localizer: localizer)

        guard estimate.isAvailable else {
            var accessibilityParts = [
                localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentUnavailableAccessibility
                ),
                disclosure,
            ]
            if estimate.isPartial {
                accessibilityParts.append(
                    localizedUnpricedAccessibility(
                        estimate,
                        models: unpricedModels,
                        localizer: localizer
                    )
                )
            }
            return TokenSummaryPresentation(
                value: "—",
                compactValue: nil,
                label: label,
                help: methodology + " " + disclosure,
                accessibilityLabel: accessibilityParts.joined(separator: " "),
                numericValue: nil,
                transitionIdentity: identity
            )
        }

        // Convert the exact aggregate. Rounding the USD amount first and then
        // converting would compound presentation rounding in the local value.
        let amount = currencyContext.amount(forUSD: estimate.costUSD)
        // Compact notation is only a width escape hatch for seven-figure
        // totals. Ordinary values keep the currency's full minor-unit detail.
        let shouldCompact = amount.roundedValue >= 1_000_000
        let fullLocalCost = amount.formatted(compact: false)
        let displayedCost = amount.formatted(compact: shouldCompact)
        let originalUSD = estimate.formattedCost(locale: localizer.locale)
        let exactHelp = localizer.localized(
            LocalizedStringResource.tokensSummaryApiEquivalentExactHelp(
                fullLocalCost,
                originalUSD,
                methodology
            )
        )
        var accessibilityParts = [
            localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentAccessibility(
                    fullLocalCost,
                    rangeSentenceForm,
                    originalUSD
                )
            ),
            disclosure,
        ]
        if estimate.isPartial {
            accessibilityParts.append(
                localizedUnpricedAccessibility(
                    estimate,
                    models: unpricedModels,
                    localizer: localizer
                )
            )
        }
        return TokenSummaryPresentation(
            value: displayedCost,
            compactValue: nil,
            label: label,
            help: exactHelp + " " + disclosure,
            accessibilityLabel: accessibilityParts.joined(separator: " "),
            numericValue: amount.numericValue,
            transitionIdentity: identity
        )
    }

    private static func localizedCurrencyLabel(
        _ context: CurrencyDisplayContext,
        localizer: AppLocalizer
    ) -> String {
        let code = context.currencyCode.rawValue
        if context.isFallback {
            return localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentCurrencyFallbackLabel(code)
            )
        }
        if context.isStale {
            return localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentCurrencyStaleLabel(code)
            )
        }
        return code
    }

    private static func localizedUnpricedModels(
        _ estimate: ApiCostEstimate,
        localizer: AppLocalizer
    ) -> String {
        estimate.unpricedModels
            .map { $0.localizedDescription(using: localizer) }
            .formatted(
                .list(type: .and, width: .standard)
                    .locale(localizer.locale)
            )
    }

    private static func localizedUnpricedAccessibility(
        _ estimate: ApiCostEstimate,
        models: String,
        localizer: AppLocalizer
    ) -> String {
        localizer.localized(
            LocalizedStringResource.tokensSummaryApiEquivalentUnpricedAccessibility(
                estimate.unpricedTokens,
                models
            )
        )
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
        _ context: CurrencyDisplayContext,
        localizer: AppLocalizer
    ) -> String {
        let effectiveCode = context.currencyCode.rawValue
        let requestedCode = context.requestedCode.rawValue

        if context.isFallback {
            var parts = [
                localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentCurrencyFallbackNoRate(
                        requestedCode
                    )
                ),
                localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentCurrencyFallbackOriginalUsd
                ),
            ]
            if let fetchedAt = context.fetchedAt {
                parts.append(
                    localizer.localized(
                        LocalizedStringResource.tokensSummaryApiEquivalentCurrencyFallbackLastFetched(
                            fetchedAtText(fetchedAt, locale: localizer.locale)
                        )
                    )
                )
            }
            return parts.joined(separator: " ")
        }

        var parts = [
            localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentCurrencyRate(
                    formatRate(context.rate, locale: localizer.locale),
                    effectiveCode
                )
            ),
        ]

        if context.currencyCode == .usd {
            parts.append(
                localizer.localized(
                    LocalizedStringResource.tokensSummaryApiEquivalentCurrencyUsdBase
                )
            )
        } else {
            if let rateDate = context.rateDate {
                parts.append(
                    localizer.localized(
                        LocalizedStringResource.tokensSummaryApiEquivalentCurrencyRateDate(
                            CurrencyAmountFormatting.rateDateText(
                                rateDate,
                                locale: localizer.locale
                            )
                        )
                    )
                )
            } else {
                parts.append(
                    localizer.localized(
                        LocalizedStringResource.tokensSummaryApiEquivalentCurrencyRateDateUnavailable
                    )
                )
            }
            if let fetchedAt = context.fetchedAt {
                parts.append(
                    localizer.localized(
                        LocalizedStringResource.tokensSummaryApiEquivalentCurrencyFetched(
                            fetchedAtText(fetchedAt, locale: localizer.locale)
                        )
                    )
                )
            } else {
                parts.append(
                    localizer.localized(
                        LocalizedStringResource.tokensSummaryApiEquivalentCurrencyFetchUnavailable
                    )
                )
            }
            parts.append(
                localizer.localized(
                    context.isStale
                        ? LocalizedStringResource.tokensSummaryApiEquivalentCurrencyStatusStale
                        : LocalizedStringResource.tokensSummaryApiEquivalentCurrencyStatusCurrent
                )
            )
        }

        return parts.joined(separator: " ")
    }

    private static func fetchedAtText(_ date: Date, locale: Locale) -> String {
        Date.FormatStyle()
            .year()
            .month()
            .day()
            .hour()
            .minute()
            .second()
            .locale(locale)
            .format(date)
    }

    private static func formatRate(_ rate: Decimal, locale: Locale) -> String {
        rate.formatted(
            .number
                .precision(.fractionLength(0...8))
                .locale(locale)
        )
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
    let currencyContext: CurrencyDisplayContext
    let accessibilityIdentifier: String

    init(
        perAgent: [TokenOdometerModel.AgentTokens],
        metric: TokenSummaryMetric,
        range: TokenRange,
        hasLoaded: Bool,
        currencyContext: CurrencyDisplayContext = .usd,
        accessibilityIdentifier: String = "tokens.summary.hero"
    ) {
        self.perAgent = perAgent
        self.metric = metric
        self.range = range
        self.hasLoaded = hasLoaded
        self.currencyContext = currencyContext
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    @Environment(\.locale) private var locale
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
            currencyContext: currencyContext,
            locale: locale
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
                    .minimumScaleFactor(0.6)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.label)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if let compactValue = presentation.compactValue {
                    Text(compactValue)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: Self.fixedHeight,
            maxHeight: Self.fixedHeight,
            alignment: .topLeading
        )
        .help(presentation.help)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
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
