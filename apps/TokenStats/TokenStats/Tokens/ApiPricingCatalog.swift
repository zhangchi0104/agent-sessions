//
//  ApiPricingCatalog.swift
//  TokenStats
//
//  Standard API list-price estimates for Model-attributed Token Odometer
//  records. This is an informational API-equivalent value, not an invoice or
//  an authoritative subscription Usage Window.
//

import Foundation

/// The Coding Agent whose model namespace a pricing rule belongs to.
///
/// This deliberately stays separate from `CodingAgentID`: the pricing catalog
/// is a nonisolated pure domain, while the app's agent registry is UI-owned.
nonisolated enum ApiPricingAgent: String, Hashable, Sendable {
    case claudeCode
    case codex

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

nonisolated extension ApiPricingAgent {
    @MainActor
    init?(_ agentID: CodingAgentID) {
        switch agentID {
        case .claudeCode: self = .claudeCode
        case .codex: self = .codex
        case .cursor: return nil
        }
    }
}

/// A calendar-only date, matching .NET's `DateOnly` pricing boundaries.
nonisolated struct ApiPricingDate: Equatable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        precondition(year > 0, "A pricing date must have a valid year.")
        precondition((1...12).contains(month), "A pricing date must have a valid month.")
        precondition((1...31).contains(day), "A pricing date must have a valid day.")
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(
            year: components.year ?? 1,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    init?(dayKey: String) {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              year > 0,
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    static var today: ApiPricingDate {
        ApiPricingDate(Date())
    }

    static func < (lhs: ApiPricingDate, rhs: ApiPricingDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

/// Standard API list prices in USD per million tokens.
nonisolated struct ApiTokenRates: Equatable, Sendable {
    let rawInput: Decimal
    let cacheRead: Decimal
    let output: Decimal
    /// Official cache-write price when separately published. Current
    /// transcripts do not expose a reliable billable cache-write Token Kind,
    /// so the estimator records but does not apply this field.
    let cacheWrite: Decimal?

    init(
        rawInput: Decimal,
        cacheRead: Decimal,
        output: Decimal,
        cacheWrite: Decimal? = nil
    ) {
        self.rawInput = rawInput
        self.cacheRead = cacheRead
        self.output = output
        self.cacheWrite = cacheWrite
    }
}

nonisolated struct ApiLongContextPricing: Equatable, Sendable {
    let inputTokensAbove: Int
    let rates: ApiTokenRates
}

/// Why a price observation starts being used on a particular calendar day.
/// Providers do not always publish an effective date; in that case TokenStats
/// uses the day it verified the official price and records that weaker basis
/// instead of inventing provider history.
nonisolated enum ApiPriceBoundaryBasis: String, Equatable, Sendable {
    case catalogBaseline
    case providerEffectiveDate
    case observedAt
}

/// One immutable official-price observation. A price change appends another
/// observation and closes the previous interval; existing observations are
/// never edited into the new price.
nonisolated struct ApiPriceObservation: Equatable, Sendable {
    let id: String
    let agent: ApiPricingAgent
    let modelPrefix: String
    let rates: ApiTokenRates
    let observedAt: ApiPricingDate
    let fromInclusive: ApiPricingDate?
    let untilExclusive: ApiPricingDate?
    let boundaryBasis: ApiPriceBoundaryBasis
    let sourceURL: String
    let longContext: ApiLongContextPricing?
    let promotionGuaranteedThrough: ApiPricingDate?

    init(
        id: String,
        agent: ApiPricingAgent,
        modelPrefix: String,
        rates: ApiTokenRates,
        observedAt: ApiPricingDate,
        fromInclusive: ApiPricingDate?,
        untilExclusive: ApiPricingDate?,
        boundaryBasis: ApiPriceBoundaryBasis,
        sourceURL: String,
        longContext: ApiLongContextPricing? = nil,
        promotionGuaranteedThrough: ApiPricingDate? = nil
    ) {
        self.id = id
        self.agent = agent
        self.modelPrefix = modelPrefix
        self.rates = rates
        self.observedAt = observedAt
        self.fromInclusive = fromInclusive
        self.untilExclusive = untilExclusive
        self.boundaryBasis = boundaryBasis
        self.sourceURL = sourceURL
        self.longContext = longContext
        self.promotionGuaranteedThrough = promotionGuaranteedThrough
    }
}

/// One Model-attributed slice in the current macOS Token Odometer shape.
nonisolated struct ApiModelUsage: Equatable, Sendable {
    let agent: ApiPricingAgent
    let model: ModelName
    let usage: TokenUsage
    /// The local calendar day on which this usage occurred. Nil is retained
    /// for aggregate callers and falls back to the estimate's pricing date.
    let pricingDate: ApiPricingDate?

    init(
        agent: ApiPricingAgent,
        model: ModelName,
        usage: TokenUsage,
        pricingDate: ApiPricingDate? = nil
    ) {
        self.agent = agent
        self.model = model
        self.usage = usage
        self.pricingDate = pricingDate
    }

    @MainActor
    init?(
        agentID: CodingAgentID,
        model: ModelName,
        usage: TokenUsage,
        pricingDate: ApiPricingDate? = nil
    ) {
        guard let agent = ApiPricingAgent(agentID) else { return nil }
        self.init(
            agent: agent,
            model: model,
            usage: usage,
            pricingDate: pricingDate
        )
    }
}

/// A semantic description of usage that the USD pricing catalog could not
/// price. Provider Model IDs stay invariant; only app-owned fallback wording
/// is localized at the presentation boundary.
nonisolated enum ApiUnpricedModel: Equatable, Hashable, Sendable {
    case model(agent: ApiPricingAgent, model: ModelName)
    case transcriptUnattributed

    fileprivate var stableSortKey: String {
        switch self {
        case .model(let agent, let model):
            return "\(agent.displayName):\(model.fallbackName)"
        case .transcriptUnattributed:
            return "unknown transcript model"
        }
    }

    func localizedDescription(using localizer: AppLocalizer) -> String {
        switch self {
        case .model(let agent, let model):
            return localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentUnpricedModelLabel(
                    agent.displayName,
                    model.localizedDisplayName(using: localizer)
                )
            )
        case .transcriptUnattributed:
            return localizer.localized(
                LocalizedStringResource.tokensSummaryApiEquivalentUnpricedTranscriptModelLabel
            )
        }
    }
}

nonisolated struct ApiCostEstimate: Equatable, Sendable {
    /// The exact aggregate before presentation rounding.
    let costUSD: Decimal
    let pricedTokens: Int
    let unpricedTokens: Int
    let unpricedModels: [ApiUnpricedModel]

    var isAvailable: Bool { pricedTokens > 0 }
    var isPartial: Bool { unpricedTokens > 0 }

    /// The Windows behavior: round the final non-negative aggregate upward once
    /// to the nearest cent, rather than rounding each Model or Token Kind.
    var roundedCostUSD: Decimal {
        var source = costUSD
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .up)
        return rounded
    }

    /// Invariant, fixed-two-decimal presentation used by the Windows client.
    var formattedCostUSD: String {
        guard isAvailable else { return "—" }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let amount = formatter.string(
            from: NSDecimalNumber(decimal: roundedCostUSD)
        ) ?? "0.00"
        return "$\(amount)"
    }

    /// UI-facing spelling; `formattedCostUSD` remains explicit at domain call
    /// sites that also inspect the unrounded `costUSD`.
    func formattedCost(locale: Locale) -> String {
        guard isAvailable else { return "—" }
        return roundedCostUSD.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(2))
                .locale(locale)
        )
    }

}

/// Standard list-price catalog kept in lockstep with Windows
/// `TokenStats.Core.ApiPricingCatalog`.
nonisolated enum ApiPricingCatalog {
    static let lastReviewed = ApiPricingDate(year: 2026, month: 8, day: 24)
    static let revision = "2026-08-24"

    static let openAIPricingSource =
        "https://developers.openai.com/api/docs/pricing"

    static let anthropicPricingSource =
        "https://platform.claude.com/docs/en/about-claude/pricing"

    static let priceObservations: [ApiPriceObservation] = [
        // OpenAI's prior public rate remains immutable for usage before the
        // next verified observation. The current official page does not state
        // when the reduction became effective, so 2026-08-24 is deliberately
        // an observation boundary rather than a claimed provider effective date.
        openAI(
            "gpt-5.6-sol",
            "5",
            "0.50",
            "30",
            id: "openai.gpt-5.6-sol.observed-2026-08-04",
            observedAt: ApiPricingDate(year: 2026, month: 8, day: 4),
            untilExclusive: ApiPricingDate(year: 2026, month: 8, day: 24)
        ),
        openAI(
            "gpt-5.6-sol",
            "4",
            "0.40",
            "20",
            id: "openai.gpt-5.6-sol.observed-2026-08-24",
            observedAt: ApiPricingDate(year: 2026, month: 8, day: 24),
            fromInclusive: ApiPricingDate(year: 2026, month: 8, day: 24),
            boundaryBasis: .observedAt,
            sourceURL: "https://developers.openai.com/api/docs/models/gpt-5.6-sol",
            cacheWrite: "5",
            longContext: ("8", "0.80", "10", "30"),
            promotionGuaranteedThrough: ApiPricingDate(
                year: 2026,
                month: 11,
                day: 21
            )
        ),
        openAI("gpt-5.6-terra", "2", "0.20", "12"),
        openAI("gpt-5.6-luna", "0.20", "0.02", "1.20"),
        openAI(
            "gpt-5.6",
            "5",
            "0.50",
            "30",
            id: "openai.gpt-5.6-alias.observed-2026-08-04",
            observedAt: ApiPricingDate(year: 2026, month: 8, day: 4),
            untilExclusive: ApiPricingDate(year: 2026, month: 8, day: 24)
        ),
        openAI(
            "gpt-5.6",
            "4",
            "0.40",
            "20",
            id: "openai.gpt-5.6-alias.observed-2026-08-24",
            observedAt: ApiPricingDate(year: 2026, month: 8, day: 24),
            fromInclusive: ApiPricingDate(year: 2026, month: 8, day: 24),
            boundaryBasis: .observedAt,
            sourceURL: "https://developers.openai.com/api/docs/models/gpt-5.6-sol",
            cacheWrite: "5",
            longContext: ("8", "0.80", "10", "30"),
            promotionGuaranteedThrough: ApiPricingDate(
                year: 2026,
                month: 11,
                day: 21
            )
        ),
        openAI("gpt-5.5", "5", "0.50", "30"),
        openAI("gpt-5.4", "2.50", "0.25", "15"),
        openAI("gpt-5.3-codex", "1.75", "0.175", "14"),
        openAI("gpt-5.2-codex", "1.75", "0.175", "14"),
        openAI("gpt-5.2", "1.75", "0.175", "14"),
        openAI("gpt-5.1-codex-mini", "0.25", "0.025", "2"),
        openAI("gpt-5.1-codex-max", "1.25", "0.125", "10"),
        openAI("gpt-5.1-codex", "1.25", "0.125", "10"),
        openAI("gpt-5.1", "1.25", "0.125", "10"),
        openAI("gpt-5-codex", "1.25", "0.125", "10"),
        openAI("gpt-5", "1.25", "0.125", "10"),
        openAI("codex-mini-latest", "1.50", "0.375", "6"),

        anthropic("claude-fable-5", "10", "1", "50"),
        anthropic("claude-mythos-5", "10", "1", "50"),
        anthropic("claude-opus-5", "5", "0.50", "25"),
        anthropic("claude-opus-4-8", "5", "0.50", "25"),
        anthropic("claude-opus-4-7", "5", "0.50", "25"),
        anthropic("claude-opus-4-6", "5", "0.50", "25"),
        anthropic("claude-opus-4-5", "5", "0.50", "25"),
        anthropic("claude-opus-4-1", "15", "1.50", "75"),
        anthropic("claude-opus-4", "15", "1.50", "75"),

        // Sonnet 5 has an introductory list price through 2026-08-31.
        anthropic(
            "claude-sonnet-5",
            "2",
            "0.20",
            "10",
            untilExclusive: ApiPricingDate(year: 2026, month: 9, day: 1)
        ),
        anthropic(
            "claude-sonnet-5",
            "3",
            "0.30",
            "15",
            fromInclusive: ApiPricingDate(year: 2026, month: 9, day: 1)
        ),
        anthropic("claude-sonnet-4-6", "3", "0.30", "15"),
        anthropic("claude-sonnet-4-5", "3", "0.30", "15"),
        anthropic("claude-sonnet-4", "3", "0.30", "15"),
        anthropic("claude-3-7-sonnet", "3", "0.30", "15"),
        anthropic("claude-3-5-sonnet", "3", "0.30", "15"),
        anthropic("claude-haiku-4-5", "1", "0.10", "5"),
        anthropic("claude-3-5-haiku", "0.80", "0.08", "4"),
        anthropic("claude-3-haiku", "0.25", "0.025", "1.25"),
        anthropic("claude-3-opus", "15", "1.50", "75"),
    ]

    /// Main-actor convenience for the exact rows exposed by
    /// `TokenOdometerModel.AgentTokens`: keep the agent id beside each Model so
    /// an unknown name is disclosed against the correct Coding Agent.
    @MainActor
    static func estimate(
        _ modelUsage: [
            (agent: CodingAgentID, model: ModelName, usage: TokenUsage)
        ],
        totalUsage: TokenUsage? = nil,
        on date: Date = Date(),
        includedKinds: Set<TokenKind> = Set(TokenKind.allCases)
    ) -> ApiCostEstimate {
        estimate(
            modelUsage: modelUsage.compactMap {
                ApiModelUsage(
                    agentID: $0.agent,
                    model: $0.model,
                    usage: $0.usage
                )
            },
            totalUsage: totalUsage,
            pricingDate: ApiPricingDate(date),
            includedKinds: includedKinds
        )
    }

    /// Nonisolated convenience for callers that already use the pricing-domain
    /// agent identity.
    static func estimate(
        _ modelUsage: [ApiModelUsage],
        totalUsage: TokenUsage? = nil,
        on date: Date = Date(),
        includedKinds: Set<TokenKind> = Set(TokenKind.allCases)
    ) -> ApiCostEstimate {
        estimate(
            modelUsage: modelUsage,
            totalUsage: totalUsage,
            pricingDate: ApiPricingDate(date),
            includedKinds: includedKinds
        )
    }

    /// Estimate a set of current `ModelName + TokenUsage` rows.
    ///
    /// `totalUsage` is optional because the reader normally attributes every
    /// token to a Model (including `.unattributed`). When supplied, any
    /// non-negative remainder not represented by `modelUsage` is disclosed as
    /// a semantic unattributed-transcript marker.
    static func estimate(
        modelUsage: [ApiModelUsage],
        totalUsage: TokenUsage? = nil,
        pricingDate: ApiPricingDate = .today,
        includedKinds: Set<TokenKind> = Set(TokenKind.allCases)
    ) -> ApiCostEstimate {
        var aggregateCost = Decimal.zero
        var pricedTokens = 0
        var unpricedTokens = 0
        var unpricedByFoldedName: [String: ApiUnpricedModel] = [:]
        var attributed = TokenUsage()

        func addUnpricedModel(_ model: ApiUnpricedModel) {
            let folded = model.stableSortKey.lowercased()
            if unpricedByFoldedName[folded] == nil {
                unpricedByFoldedName[folded] = model
            }
        }

        for item in modelUsage {
            attributed.add(item.usage)
            let selectedTokens = selectedTotal(
                item.usage,
                includedKinds: includedKinds
            )
            guard selectedTokens > 0 else { continue }

            if case .named(let model) = item.model,
               let rates = rates(
                   for: item.agent,
                   model: model,
                   pricingDate: item.pricingDate ?? pricingDate
               ) {
                aggregateCost += cost(
                    of: item.usage,
                    at: rates,
                    includedKinds: includedKinds
                )
                pricedTokens += selectedTokens
            } else {
                unpricedTokens += selectedTokens
                addUnpricedModel(.model(agent: item.agent, model: item.model))
            }
        }

        if let totalUsage {
            let unattributed = subtractNonNegative(totalUsage, attributed)
            let selectedUnattributed = selectedTotal(
                unattributed,
                includedKinds: includedKinds
            )
            if selectedUnattributed > 0 {
                unpricedTokens += selectedUnattributed
                addUnpricedModel(.transcriptUnattributed)
            }
        }

        let unpricedModels = unpricedByFoldedName.values.sorted {
            let left = $0.stableSortKey.lowercased()
            let right = $1.stableSortKey.lowercased()
            return left == right ? $0.stableSortKey < $1.stableSortKey : left < right
        }
        return ApiCostEstimate(
            costUSD: aggregateCost,
            pricedTokens: pricedTokens,
            unpricedTokens: unpricedTokens,
            unpricedModels: unpricedModels
        )
    }

    static func rates(
        for agent: ApiPricingAgent,
        model: String,
        pricingDate: ApiPricingDate
    ) -> ApiTokenRates? {
        observation(
            for: agent,
            model: model,
            pricingDate: pricingDate
        )?.rates
    }

    static func observation(
        for agent: ApiPricingAgent,
        model: String,
        pricingDate: ApiPricingDate
    ) -> ApiPriceObservation? {
        guard !model.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return nil
        }

        return priceObservations
            .filter { observation in
                observation.agent == agent &&
                    matches(
                        modelPrefix: observation.modelPrefix,
                        model: model
                    ) &&
                    (observation.fromInclusive == nil ||
                     pricingDate >= observation.fromInclusive!) &&
                    (observation.untilExclusive == nil ||
                     pricingDate < observation.untilExclusive!)
            }
            .max { $0.modelPrefix.count < $1.modelPrefix.count }
    }

    private static func matches(modelPrefix: String, model: String) -> Bool {
        if model.compare(
            modelPrefix,
            options: .caseInsensitive
        ) == .orderedSame {
            return true
        }

        let snapshotPrefix = modelPrefix + "-"
        guard model.range(
            of: snapshotPrefix,
            options: [.anchored, .caseInsensitive]
        ) != nil else {
            return false
        }

        let suffixStart = model.index(
            model.startIndex,
            offsetBy: snapshotPrefix.count
        )
        let suffix = model[suffixStart...]
        return suffix.hasPrefix("20") &&
            suffix.unicodeScalars.allSatisfy { scalar in
                scalar.value == 45 || (48...57).contains(scalar.value)
            }
    }

    private static func selectedTotal(
        _ usage: TokenUsage,
        includedKinds: Set<TokenKind>
    ) -> Int {
        TokenKind.allCases
            .filter(includedKinds.contains)
            .reduce(0) { $0 + usage.amount(of: $1) }
    }

    private static func cost(
        of usage: TokenUsage,
        at rates: ApiTokenRates,
        includedKinds: Set<TokenKind>
    ) -> Decimal {
        var result = Decimal.zero
        if includedKinds.contains(.directInput) {
            result += Decimal(usage.inputTokens) * rates.rawInput
        }
        if includedKinds.contains(.output) {
            result += Decimal(usage.outputTokens) * rates.output
        }
        if includedKinds.contains(.cacheRead) {
            result += Decimal(usage.cacheReadTokens) * rates.cacheRead
        }
        return result / Decimal(1_000_000)
    }

    private static func subtractNonNegative(
        _ total: TokenUsage,
        _ attributed: TokenUsage
    ) -> TokenUsage {
        var remainder = TokenUsage()
        remainder.inputTokens = max(total.inputTokens - attributed.inputTokens, 0)
        remainder.outputTokens = max(total.outputTokens - attributed.outputTokens, 0)
        remainder.cacheReadTokens = max(
            total.cacheReadTokens - attributed.cacheReadTokens,
            0
        )
        return remainder
    }

    private static func openAI(
        _ modelPrefix: String,
        _ rawInput: String,
        _ cacheRead: String,
        _ output: String,
        id: String? = nil,
        observedAt: ApiPricingDate = ApiPricingDate(
            year: 2026,
            month: 8,
            day: 4
        ),
        fromInclusive: ApiPricingDate? = nil,
        untilExclusive: ApiPricingDate? = nil,
        boundaryBasis: ApiPriceBoundaryBasis = .catalogBaseline,
        sourceURL: String = openAIPricingSource,
        cacheWrite: String? = nil,
        longContext: (
            rawInput: String,
            cacheRead: String,
            cacheWrite: String,
            output: String
        )? = nil,
        promotionGuaranteedThrough: ApiPricingDate? = nil
    ) -> ApiPriceObservation {
        return ApiPriceObservation(
            id: id ?? "openai.\(modelPrefix).baseline-2026-08-04",
            agent: .codex,
            modelPrefix: modelPrefix,
            rates: ApiTokenRates(
                rawInput: decimal(rawInput),
                cacheRead: decimal(cacheRead),
                output: decimal(output),
                cacheWrite: cacheWrite.map(decimal)
            ),
            observedAt: observedAt,
            fromInclusive: fromInclusive,
            untilExclusive: untilExclusive,
            boundaryBasis: boundaryBasis,
            sourceURL: sourceURL,
            longContext: longContext.map {
                ApiLongContextPricing(
                    inputTokensAbove: 272_000,
                    rates: ApiTokenRates(
                        rawInput: decimal($0.rawInput),
                        cacheRead: decimal($0.cacheRead),
                        output: decimal($0.output),
                        cacheWrite: decimal($0.cacheWrite)
                    )
                )
            },
            promotionGuaranteedThrough: promotionGuaranteedThrough
        )
    }

    private static func anthropic(
        _ modelPrefix: String,
        _ rawInput: String,
        _ cacheRead: String,
        _ output: String,
        fromInclusive: ApiPricingDate? = nil,
        untilExclusive: ApiPricingDate? = nil
    ) -> ApiPriceObservation {
        ApiPriceObservation(
            id: "anthropic.\(modelPrefix).\(fromInclusive.map(dateKey) ?? "baseline-2026-08-04")",
            agent: .claudeCode,
            modelPrefix: modelPrefix,
            rates: ApiTokenRates(
                rawInput: decimal(rawInput),
                cacheRead: decimal(cacheRead),
                output: decimal(output)
            ),
            observedAt: ApiPricingDate(year: 2026, month: 8, day: 4),
            fromInclusive: fromInclusive,
            untilExclusive: untilExclusive,
            boundaryBasis: fromInclusive == nil
                ? .catalogBaseline
                : .providerEffectiveDate,
            sourceURL: anthropicPricingSource
        )
    }

    private static func dateKey(_ date: ApiPricingDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    private static func decimal(_ value: String) -> Decimal {
        guard let result = Decimal(
            string: value,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            preconditionFailure("Invalid API price: \(value)")
        }
        return result
    }
}
