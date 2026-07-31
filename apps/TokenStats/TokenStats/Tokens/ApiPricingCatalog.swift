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
    init(_ agentID: CodingAgentID) {
        switch agentID {
        case .claudeCode: self = .claudeCode
        case .codex: self = .codex
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
    let cacheWrite: Decimal
    let cacheWrite1Hour: Decimal
    let cacheRead: Decimal
    let output: Decimal
}

/// One Model-attributed slice in the current macOS Token Odometer shape.
nonisolated struct ApiModelUsage: Equatable, Sendable {
    let agent: ApiPricingAgent
    let model: ModelName
    let usage: TokenUsage

    init(agent: ApiPricingAgent, model: ModelName, usage: TokenUsage) {
        self.agent = agent
        self.model = model
        self.usage = usage
    }

    @MainActor
    init(agentID: CodingAgentID, model: ModelName, usage: TokenUsage) {
        self.init(agent: ApiPricingAgent(agentID), model: model, usage: usage)
    }
}

nonisolated struct ApiCostEstimate: Equatable, Sendable {
    /// The exact aggregate before presentation rounding.
    let costUSD: Decimal
    let pricedTokens: Int
    let unpricedTokens: Int
    let unpricedModels: [String]

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
    var formattedCost: String { formattedCostUSD }
}

/// Standard list-price catalog kept in lockstep with Windows
/// `TokenStats.Core.ApiPricingCatalog`.
nonisolated enum ApiPricingCatalog {
    static let lastReviewed = ApiPricingDate(year: 2026, month: 7, day: 27)

    static let openAIPricingSource =
        "https://developers.openai.com/api/docs/models"

    static let anthropicPricingSource =
        "https://platform.claude.com/docs/en/about-claude/pricing"

    private static let rules: [PricingRule] = [
        // OpenAI GPT-5.6 cache writes are billed at 1.25x raw input.
        openAI("gpt-5.6-sol", "5", "6.25", "0.50", "30"),
        openAI("gpt-5.6-terra", "2.50", "3.125", "0.25", "15"),
        openAI("gpt-5.6-luna", "1", "1.25", "0.10", "6"),
        openAI("gpt-5.6", "5", "6.25", "0.50", "30"),
        openAI("gpt-5.5", "5", "5", "0.50", "30"),
        openAI("gpt-5.4", "2.50", "2.50", "0.25", "15"),
        openAI("gpt-5.3-codex", "1.75", "1.75", "0.175", "14"),
        openAI("gpt-5.2-codex", "1.75", "1.75", "0.175", "14"),
        openAI("gpt-5.2", "1.75", "1.75", "0.175", "14"),
        openAI("gpt-5.1-codex-mini", "0.25", "0.25", "0.025", "2"),
        openAI("gpt-5.1-codex-max", "1.25", "1.25", "0.125", "10"),
        openAI("gpt-5.1-codex", "1.25", "1.25", "0.125", "10"),
        openAI("gpt-5.1", "1.25", "1.25", "0.125", "10"),
        openAI("gpt-5-codex", "1.25", "1.25", "0.125", "10"),
        openAI("gpt-5", "1.25", "1.25", "0.125", "10"),
        openAI("codex-mini-latest", "1.50", "1.50", "0.375", "6"),

        anthropic("claude-fable-5", "10", "12.50", "20", "1", "50"),
        anthropic("claude-mythos-5", "10", "12.50", "20", "1", "50"),
        anthropic("claude-opus-5", "5", "6.25", "10", "0.50", "25"),
        anthropic("claude-opus-4-8", "5", "6.25", "10", "0.50", "25"),
        anthropic("claude-opus-4-7", "5", "6.25", "10", "0.50", "25"),
        anthropic("claude-opus-4-6", "5", "6.25", "10", "0.50", "25"),
        anthropic("claude-opus-4-5", "5", "6.25", "10", "0.50", "25"),
        anthropic("claude-opus-4-1", "15", "18.75", "30", "1.50", "75"),
        anthropic("claude-opus-4", "15", "18.75", "30", "1.50", "75"),

        // Sonnet 5 has an introductory list price through 2026-08-31.
        anthropic(
            "claude-sonnet-5",
            "2",
            "2.50",
            "4",
            "0.20",
            "10",
            untilExclusive: ApiPricingDate(year: 2026, month: 9, day: 1)
        ),
        anthropic(
            "claude-sonnet-5",
            "3",
            "3.75",
            "6",
            "0.30",
            "15",
            fromInclusive: ApiPricingDate(year: 2026, month: 9, day: 1)
        ),
        anthropic("claude-sonnet-4-6", "3", "3.75", "6", "0.30", "15"),
        anthropic("claude-sonnet-4-5", "3", "3.75", "6", "0.30", "15"),
        anthropic("claude-sonnet-4", "3", "3.75", "6", "0.30", "15"),
        anthropic("claude-3-7-sonnet", "3", "3.75", "6", "0.30", "15"),
        anthropic("claude-3-5-sonnet", "3", "3.75", "6", "0.30", "15"),
        anthropic("claude-haiku-4-5", "1", "1.25", "2", "0.10", "5"),
        anthropic("claude-3-5-haiku", "0.80", "1", "1.60", "0.08", "4"),
        anthropic("claude-3-haiku", "0.25", "0.3125", "0.50", "0.025", "1.25"),
        anthropic("claude-3-opus", "15", "18.75", "30", "1.50", "75"),
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
            modelUsage: modelUsage.map {
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
    /// `unknown transcript model`, matching Windows' defensive fallback.
    static func estimate(
        modelUsage: [ApiModelUsage],
        totalUsage: TokenUsage? = nil,
        pricingDate: ApiPricingDate = .today,
        includedKinds: Set<TokenKind> = Set(TokenKind.allCases)
    ) -> ApiCostEstimate {
        var aggregateCost = Decimal.zero
        var pricedTokens = 0
        var unpricedTokens = 0
        var unpricedByFoldedName: [String: String] = [:]
        var attributed = TokenUsage()

        func addUnpricedModel(_ label: String) {
            let folded = label.lowercased()
            if unpricedByFoldedName[folded] == nil {
                unpricedByFoldedName[folded] = label
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
                   pricingDate: pricingDate
               ) {
                aggregateCost += cost(
                    of: item.usage,
                    at: rates,
                    includedKinds: includedKinds
                )
                pricedTokens += selectedTokens
            } else {
                unpricedTokens += selectedTokens
                addUnpricedModel(
                    "\(item.agent.displayName): " +
                    "\(item.model == .unattributed ? "unknown model" : item.model.displayName)"
                )
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
                addUnpricedModel("unknown transcript model")
            }
        }

        let unpricedModels = unpricedByFoldedName.values.sorted {
            let left = $0.lowercased()
            let right = $1.lowercased()
            return left == right ? $0 < $1 : left < right
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
        guard !model.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return nil
        }

        return rules
            .filter { rule in
                rule.agent == agent &&
                    matches(modelPrefix: rule.modelPrefix, model: model) &&
                    (rule.fromInclusive == nil ||
                     pricingDate >= rule.fromInclusive!) &&
                    (rule.untilExclusive == nil ||
                     pricingDate < rule.untilExclusive!)
            }
            .max { $0.modelPrefix.count < $1.modelPrefix.count }?
            .rates
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
        if includedKinds.contains(.cacheWrite) {
            // TokenUsage currently has no cache-write TTL split. Windows prices
            // such writes at the default 5-minute rate, never the 1-hour rate.
            result += Decimal(usage.cacheCreationTokens) * rates.cacheWrite
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
        remainder.cacheCreationTokens = max(
            total.cacheCreationTokens - attributed.cacheCreationTokens,
            0
        )
        remainder.cacheReadTokens = max(
            total.cacheReadTokens - attributed.cacheReadTokens,
            0
        )
        return remainder
    }

    private static func openAI(
        _ modelPrefix: String,
        _ rawInput: String,
        _ cacheWrite: String,
        _ cacheRead: String,
        _ output: String
    ) -> PricingRule {
        let write = decimal(cacheWrite)
        return PricingRule(
            agent: .codex,
            modelPrefix: modelPrefix,
            rates: ApiTokenRates(
                rawInput: decimal(rawInput),
                cacheWrite: write,
                cacheWrite1Hour: write,
                cacheRead: decimal(cacheRead),
                output: decimal(output)
            )
        )
    }

    private static func anthropic(
        _ modelPrefix: String,
        _ rawInput: String,
        _ cacheWrite: String,
        _ cacheWrite1Hour: String,
        _ cacheRead: String,
        _ output: String,
        fromInclusive: ApiPricingDate? = nil,
        untilExclusive: ApiPricingDate? = nil
    ) -> PricingRule {
        PricingRule(
            agent: .claudeCode,
            modelPrefix: modelPrefix,
            rates: ApiTokenRates(
                rawInput: decimal(rawInput),
                cacheWrite: decimal(cacheWrite),
                cacheWrite1Hour: decimal(cacheWrite1Hour),
                cacheRead: decimal(cacheRead),
                output: decimal(output)
            ),
            fromInclusive: fromInclusive,
            untilExclusive: untilExclusive
        )
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

    private struct PricingRule: Sendable {
        let agent: ApiPricingAgent
        let modelPrefix: String
        let rates: ApiTokenRates
        var fromInclusive: ApiPricingDate?
        var untilExclusive: ApiPricingDate?
    }
}
