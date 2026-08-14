//
//  TokenSummaryHero.swift
//  TokenStats
//
//  The fixed objective summary at the top of the Tokens tab. Billing tokens
//  lead, with an API-equivalent list-price estimate beneath; neither changes
//  the raw Token Odometer or the Token Kind table projection.
//

import SwiftUI

/// Both objective Tokens-tab readings, built together from one agent set.
@MainActor
struct TokenSummaryReadings: Equatable {
    let billing: TokenSummaryPresentation
    let apiEquivalent: TokenApiEquivalentPresentation

    static func make(
        perAgent: [TokenOdometerModel.AgentTokens],
        range: TokenRange,
        hasLoaded: Bool,
        pricingDate: Date = Date(),
        currencyContext: CurrencyDisplayContext = .usd,
        locale: Locale
    ) -> TokenSummaryReadings {
        let localizer = AppLocalizer(locale: locale)
        guard hasLoaded else {
            return TokenSummaryReadings(
                billing: .reading(range: range, localizer: localizer),
                apiEquivalent: .reading(
                    range: range,
                    currencyContext: currencyContext,
                    localizer: localizer
                )
            )
        }

        var total = TokenUsage()
        for agent in perAgent { total.add(agent.usage) }
        let usage = total.responseCount > 0 ? total : nil
        return TokenSummaryReadings(
            billing: .billing(usage: usage, range: range, localizer: localizer),
            apiEquivalent: .make(
                perAgent: perAgent,
                usage: usage,
                range: range,
                pricingDate: pricingDate,
                currencyContext: currencyContext,
                localizer: localizer
            )
        )
    }
}

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

    fileprivate static func reading(
        range: TokenRange,
        localizer: AppLocalizer
    ) -> TokenSummaryPresentation {
        let rangeSentenceForm = range.localizedSentenceForm(using: localizer)
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
            numericValue: nil
        )
    }

    fileprivate static func billing(
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
                numericValue: nil
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
                    output,
                    cacheRead
                )
            ),
            accessibilityLabel: localizer.localized(
                LocalizedStringResource.tokensSummaryBillingAccessibility(count, rangeSentenceForm)
            ),
            numericValue: Double(count)
        )
    }
}

@MainActor
struct TokenApiEquivalentPresentation: Equatable {
    let value: String
    let help: String
    let accessibilityLabel: String
    /// The semantic number behind `value`, used only by SwiftUI's native
    /// numeric transition. Nil means the reading is unavailable.
    let numericValue: Double?
    /// Identifies the semantic unit behind `numericValue`. A changed identity
    /// replaces the value with a short crossfade instead of rolling digits
    /// between unrelated currencies.
    let transitionIdentity: String

    fileprivate static func reading(
        range: TokenRange,
        currencyContext: CurrencyDisplayContext,
        localizer: AppLocalizer
    ) -> TokenApiEquivalentPresentation {
        let rangeSentenceForm = range.localizedSentenceForm(using: localizer)
        return TokenApiEquivalentPresentation(
            value: "—",
            help: localizer.localized(
                LocalizedStringResource.tokensSummaryEstimatedApiValueReadingHelp(rangeSentenceForm)
            ),
            accessibilityLabel: localizer.localized(
                LocalizedStringResource.tokensSummaryEstimatedApiValueReadingAccessibility(
                    rangeSentenceForm
                )
            ),
            numericValue: nil,
            transitionIdentity: transitionIdentity(currencyContext)
        )
    }

    fileprivate static func make(
        perAgent: [TokenOdometerModel.AgentTokens],
        usage: TokenUsage?,
        range: TokenRange,
        pricingDate: Date,
        currencyContext: CurrencyDisplayContext,
        localizer: AppLocalizer
    ) -> TokenApiEquivalentPresentation {
        let identity = transitionIdentity(currencyContext)
        let rangeSentenceForm = range.localizedSentenceForm(using: localizer)
        guard usage != nil else {
            return TokenApiEquivalentPresentation(
                value: "—",
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
            return TokenApiEquivalentPresentation(
                value: "—",
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
        return TokenApiEquivalentPresentation(
            value: displayedCost,
            help: exactHelp + " " + disclosure,
            accessibilityLabel: accessibilityParts.joined(separator: " "),
            numericValue: amount.numericValue,
            transitionIdentity: identity
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

    private static func transitionIdentity(_ currencyContext: CurrencyDisplayContext) -> String {
        [
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
    /// Stable layout contract for the primary value, its label, and the API
    /// estimate row. The table below remains content-sized; only this summary
    /// is isolated from popover height changes.
    static let valueFontSize: CGFloat = 42
    static let valueSlotHeight: CGFloat = 52
    static let fixedHeight: CGFloat = 100

    let perAgent: [TokenOdometerModel.AgentTokens]
    let range: TokenRange
    let hasLoaded: Bool
    let currencyContext: CurrencyDisplayContext
    let accessibilityIdentifier: String

    init(
        perAgent: [TokenOdometerModel.AgentTokens],
        range: TokenRange,
        hasLoaded: Bool,
        currencyContext: CurrencyDisplayContext = .usd,
        accessibilityIdentifier: String = "tokens.summary.hero"
    ) {
        self.perAgent = perAgent
        self.range = range
        self.hasLoaded = hasLoaded
        self.currencyContext = currencyContext
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False until this view has settled its first number. The initial value
    /// appears immediately, matching v1's conditionally inserted hero.
    @State private var hasPresentedNumber = false

    private var readings: TokenSummaryReadings {
        .make(
            perAgent: perAgent,
            range: range,
            hasLoaded: hasLoaded,
            currencyContext: currencyContext,
            locale: locale
        )
    }

    private func shouldAnimateBilling(_ presentation: TokenSummaryPresentation) -> Bool {
        !reduceMotion
            && hasPresentedNumber
            && presentation.numericValue != nil
    }

    var body: some View {
        let readings = self.readings

        VStack(alignment: .leading, spacing: 10) {
            billingSummary(readings.billing)
            apiEstimateRow(readings.apiEquivalent)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: Self.fixedHeight,
            maxHeight: Self.fixedHeight,
            alignment: .topLeading
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            hasPresentedNumber = readings.billing.numericValue != nil
        }
        .onChange(of: readings.billing.numericValue) { _, newValue in
            if newValue != nil { hasPresentedNumber = true }
        }
    }

    private func billingSummary(_ presentation: TokenSummaryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.value)
                // SwiftUI owns the same-unit per-digit motion as the selected
                // reporting range or transcript totals change.
                .font(.system(size: Self.valueFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(
                    .numericText(value: presentation.numericValue ?? 0)
                )
                .animation(
                    shouldAnimateBilling(presentation) ? .snappy(duration: 0.6) : nil,
                    value: presentation.numericValue
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
        .help(presentation.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func apiEstimateRow(_ presentation: TokenApiEquivalentPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LocalizedStringResource.tokensSummaryEstimatedApiValue)
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            ZStack(alignment: .trailing) {
                Text(presentation.value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(
                        .numericText(value: presentation.numericValue ?? 0)
                    )
                    .animation(
                        reduceMotion ? nil : .snappy(duration: 0.45),
                        value: presentation.numericValue
                    )
                    .id(presentation.transitionIdentity)
                    .transition(reduceMotion ? .identity : .opacity)
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.2),
                value: presentation.transitionIdentity
            )
        }
        .foregroundStyle(.secondary)
        .help(presentation.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
