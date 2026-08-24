//
//  ApiValuationHistory.swift
//  TokenStats
//
//  Durable audit snapshots of the last API-equivalent calculation made under
//  each catalog revision. These do not replace transcript truth or the live
//  estimate; they preserve what the previous calculation method produced when
//  a later official-price observation changes the catalog.
//

import Foundation

nonisolated struct ApiValuationSnapshot: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let scopeKey: String
    let catalogRevision: String
    let range: TokenRange
    let firstUsageDay: String
    let lastUsageDay: String
    let calculatedAt: Date
    /// Decimal is encoded canonically as a base-10 string so an audit snapshot
    /// never acquires binary floating-point error during a round trip.
    let exactCostUSD: String
    let pricedTokens: Int
    let unpricedTokens: Int
    let directInputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let priceObservationIDs: [String]

    var storageKey: String { "\(scopeKey)|\(catalogRevision)" }

    /// Stable SwiftUI task identity. `calculatedAt` is deliberately excluded:
    /// re-rendering an unchanged reading must not rewrite persistence.
    var contentID: String {
        [
            storageKey,
            firstUsageDay,
            lastUsageDay,
            exactCostUSD,
            String(pricedTokens),
            String(unpricedTokens),
            String(directInputTokens),
            String(outputTokens),
            String(cacheReadTokens),
            priceObservationIDs.joined(separator: ","),
        ].joined(separator: "|")
    }

    var isValidEnvelope: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !scopeKey.isEmpty
            && !catalogRevision.isEmpty
            && ApiPricingDate(dayKey: firstUsageDay) != nil
            && ApiPricingDate(dayKey: lastUsageDay) != nil
            && firstUsageDay <= lastUsageDay
            && Decimal(
                string: exactCostUSD,
                locale: Locale(identifier: "en_US_POSIX")
            ) != nil
            && pricedTokens >= 0
            && unpricedTokens >= 0
            && directInputTokens >= 0
            && outputTokens >= 0
            && cacheReadTokens >= 0
            && priceObservationIDs == Array(Set(priceObservationIDs)).sorted()
    }
}

@MainActor
struct ApiValuationCalculation {
    let estimate: ApiCostEstimate
    let snapshot: ApiValuationSnapshot

    static func make(
        perAgent: [TokenOdometerModel.AgentTokens],
        totalUsage: TokenUsage,
        range: TokenRange,
        fallbackPricingDate: ApiPricingDate,
        calculatedAt: Date = Date()
    ) -> ApiValuationCalculation {
        var rows: [ApiModelUsage] = []
        var observationIDs = Set<String>()
        var occurrenceDays: [ApiPricingDate] = []
        let agents = perAgent.compactMap { ApiPricingAgent($0.id) }

        for agent in perAgent {
            guard let pricingAgent = ApiPricingAgent(agent.id) else { continue }
            if !agent.dailyByModel.isEmpty {
                for row in agent.dailyByModel {
                    rows.append(
                        ApiModelUsage(
                            agent: pricingAgent,
                            model: row.model,
                            usage: row.usage,
                            pricingDate: row.day
                        )
                    )
                    occurrenceDays.append(row.day)
                    collectObservationID(
                        agent: pricingAgent,
                        model: row.model,
                        day: row.day,
                        into: &observationIDs
                    )
                }
            } else {
                for row in agent.byModel {
                    rows.append(
                        ApiModelUsage(
                            agent: pricingAgent,
                            model: row.model,
                            usage: row.usage
                        )
                    )
                    collectObservationID(
                        agent: pricingAgent,
                        model: row.model,
                        day: fallbackPricingDate,
                        into: &observationIDs
                    )
                }
            }
        }

        let estimate = ApiPricingCatalog.estimate(
            modelUsage: rows,
            totalUsage: totalUsage,
            pricingDate: fallbackPricingDate
        )
        let firstDay = occurrenceDays.min() ?? fallbackPricingDate
        let lastDay = occurrenceDays.max() ?? fallbackPricingDate
        let agentScope = agents
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        let snapshot = ApiValuationSnapshot(
            schemaVersion: ApiValuationSnapshot.currentSchemaVersion,
            scopeKey: "\(range.rawValue)|\(agentScope)",
            catalogRevision: ApiPricingCatalog.revision,
            range: range,
            firstUsageDay: dayKey(firstDay),
            lastUsageDay: dayKey(lastDay),
            calculatedAt: calculatedAt,
            exactCostUSD: NSDecimalNumber(decimal: estimate.costUSD).stringValue,
            pricedTokens: estimate.pricedTokens,
            unpricedTokens: estimate.unpricedTokens,
            directInputTokens: totalUsage.inputTokens,
            outputTokens: totalUsage.outputTokens,
            cacheReadTokens: totalUsage.cacheReadTokens,
            priceObservationIDs: observationIDs.sorted()
        )
        return ApiValuationCalculation(estimate: estimate, snapshot: snapshot)
    }

    private static func collectObservationID(
        agent: ApiPricingAgent,
        model: ModelName,
        day: ApiPricingDate,
        into result: inout Set<String>
    ) {
        guard case .named(let name) = model,
              let observation = ApiPricingCatalog.observation(
                  for: agent,
                  model: name,
                  pricingDate: day
              )
        else {
            return
        }
        result.insert(observation.id)
    }

    private static func dayKey(_ day: ApiPricingDate) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }
}

nonisolated struct ApiValuationHistoryStore {
    private enum Key {
        static let history = "tokens.apiValuationHistory.v1"
    }

    private enum LoadResult {
        case missing
        case loaded([ApiValuationSnapshot])
        case unreadable
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
    }

    @MainActor
    func load() -> [ApiValuationSnapshot] {
        switch loadResult() {
        case .loaded(let snapshots):
            return snapshots
        case .missing, .unreadable:
            return []
        }
    }

    /// Preserve unreadable and future-schema history byte-for-byte instead of
    /// treating it as empty and deleting prior catalog revisions on the next
    /// live calculation.
    @discardableResult
    @MainActor
    func save(_ snapshot: ApiValuationSnapshot) -> Bool {
        guard let defaults, snapshot.isValidEnvelope else { return false }
        let loaded: [ApiValuationSnapshot]
        switch loadResult() {
        case .missing:
            loaded = []
        case .loaded(let snapshots):
            loaded = snapshots
        case .unreadable:
            return false
        }
        var byKey = Dictionary(
            uniqueKeysWithValues: loaded.map { ($0.storageKey, $0) }
        )
        byKey[snapshot.storageKey] = snapshot
        let history = byKey.values.sorted {
            if $0.calculatedAt != $1.calculatedAt {
                return $0.calculatedAt < $1.calculatedAt
            }
            return $0.storageKey < $1.storageKey
        }
        guard let data = try? JSONEncoder().encode(history) else { return false }
        defaults.set(data, forKey: Key.history)
        return true
    }

    @MainActor
    private func loadResult() -> LoadResult {
        guard let defaults else { return .missing }
        guard let data = defaults.data(forKey: Key.history) else {
            return .missing
        }
        guard let decoded = try? JSONDecoder().decode(
            [ApiValuationSnapshot].self,
            from: data
        ),
            decoded.allSatisfy(\.isValidEnvelope),
            Set(decoded.map(\.storageKey)).count == decoded.count
        else {
            return .unreadable
        }
        return .loaded(decoded)
    }
}
