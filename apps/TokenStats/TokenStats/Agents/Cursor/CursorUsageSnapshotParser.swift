//
//  CursorUsageSnapshotParser.swift
//  TokenStats
//
//  Cursor DashboardService/GetCurrentPeriodUsage JSON -> the two authoritative
//  model buckets shown by Cursor's subscription dashboard.
//

import Foundation

enum CursorUsageSnapshotParser {
    static func parse(_ data: Data) throws -> [UsageWindow] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.enabled != false,
              let plan = payload.planUsage else {
            return []
        }
        let resetAt = payload.billingCycleEnd.flatMap { milliseconds in
            milliseconds > 0 ? Date(timeIntervalSince1970: milliseconds / 1_000) : nil
        }
        return [
            UsageWindow(
                identity: .cursorModels,
                percentConsumed: plan.cursorModelsPercent,
                resetAt: resetAt
            ),
            UsageWindow(
                identity: .otherModels,
                percentConsumed: plan.otherModelsPercent,
                resetAt: resetAt
            ),
        ]
    }

    private struct Payload: Decodable {
        let billingCycleEnd: Double?
        let planUsage: PlanUsage?
        let enabled: Bool?

        enum CodingKeys: String, CodingKey {
            case billingCycleEnd
            case billingCycleEndSnake = "billing_cycle_end"
            case planUsage
            case planUsageSnake = "plan_usage"
            case enabled
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled)
            billingCycleEnd = Self.flexibleDouble(
                in: values,
                keys: [.billingCycleEnd, .billingCycleEndSnake]
            )
            if enabled == false {
                planUsage = nil
            } else {
                planUsage = try values.decodeIfPresent(PlanUsage.self, forKey: .planUsage)
                    ?? values.decodeIfPresent(PlanUsage.self, forKey: .planUsageSnake)
            }
        }

        /// Connect's int64 JSON mapping uses decimal strings, while older
        /// captures and test fixtures used JSON numbers. Accept both encodings
        /// without weakening validation of the rest of the response.
        private static func flexibleDouble(
            in values: KeyedDecodingContainer<CodingKeys>,
            keys: [CodingKeys]
        ) -> Double? {
            for key in keys {
                if let number = try? values.decode(Double.self, forKey: key),
                   number.isFinite {
                    return number
                }
                if let raw = try? values.decode(String.self, forKey: key),
                   let number = Double(raw), number.isFinite {
                    return number
                }
            }
            return nil
        }
    }

    private struct PlanUsage: Decodable {
        let cursorModelsPercent: Double
        let otherModelsPercent: Double

        enum CodingKeys: String, CodingKey {
            case autoPercentUsed
            case autoPercentUsedSnake = "auto_percent_used"
            case apiPercentUsed
            case apiPercentUsedSnake = "api_percent_used"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            cursorModelsPercent = try Self.percentage(
                in: values,
                keys: [.autoPercentUsed, .autoPercentUsedSnake]
            )
            otherModelsPercent = try Self.percentage(
                in: values,
                keys: [.apiPercentUsed, .apiPercentUsedSnake]
            )
        }

        private static func percentage(
            in values: KeyedDecodingContainer<CodingKeys>,
            keys: [CodingKeys]
        ) throws -> Double {
            for key in keys where values.contains(key) {
                let value = try values.decode(Double.self, forKey: key)
                guard value.isFinite else {
                    throw DecodingError.dataCorruptedError(
                        forKey: key,
                        in: values,
                        debugDescription: "Cursor usage percentage must be finite."
                    )
                }
                return min(max(value, 0), 100)
            }
            throw DecodingError.keyNotFound(
                keys[0],
                .init(
                    codingPath: values.codingPath,
                    debugDescription: "Cursor usage response is missing an official model bucket."
                )
            )
        }
    }
}
