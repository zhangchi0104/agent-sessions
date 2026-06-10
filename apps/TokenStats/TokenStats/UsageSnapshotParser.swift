//
//  UsageSnapshotParser.swift
//  TokenStats
//
//  Pure: raw usage JSON (from the OAuth usage endpoint, see ADR-0001 and
//  docs/claude-code-integration.md) → normalized [UsageWindow].
//

import Foundation

enum UsageSnapshotParser {

    static func parse(_ data: Data) throws -> [UsageWindow] {
        let raw = try JSONDecoder().decode(RawSnapshot.self, from: data)
        let meteredWindows = [
            raw.five_hour?.window(label: "5-hour"),
            raw.seven_day?.window(label: "Weekly"),
        ].compactMap { $0 }
        return meteredWindows
    }

    /// The usage-credit balance from `extra_usage`, or nil when the plan has no
    /// enabled credit quota. Tolerant: a missing/malformed block yields nil
    /// rather than throwing, so it never sinks the metered-window parse.
    static func parseCredits(_ data: Data) -> CreditBalance? {
        guard
            let envelope = try? JSONDecoder().decode(CreditEnvelope.self, from: data),
            let extra = envelope.extra_usage,
            extra.is_enabled == true,
            let limit = extra.monthly_limit, limit > 0
        else { return nil }
        return CreditBalance(
            usedCents: extra.used_credits ?? 0,
            limitCents: limit,
            utilization: extra.utilization ?? 0,
            currency: extra.currency ?? "USD"
        )
    }

    private struct CreditEnvelope: Decodable {
        let extra_usage: ExtraUsage?
    }

    private struct ExtraUsage: Decodable {
        let is_enabled: Bool?
        let monthly_limit: Double?
        let used_credits: Double?
        let utilization: Double?
        let currency: String?
    }

    private struct RawSnapshot: Decodable {
        let five_hour: RawWindow?
        let seven_day: RawWindow?

        enum CodingKeys: String, CodingKey {
            case five_hour, seven_day
        }

        init(from decoder: Decoder) throws {
            // A present-but-malformed block (e.g. missing resets_at) must not
            // sink the whole snapshot — decode each window independently.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            five_hour = try? container.decodeIfPresent(RawWindow.self, forKey: .five_hour)
            seven_day = try? container.decodeIfPresent(RawWindow.self, forKey: .seven_day)
        }
    }

    private struct RawWindow: Decodable {
        // Empirically (2026-05-28): `utilization` is already a percent (0–100),
        // and `resets_at` is either an ISO-8601 timestamp string or explicit
        // null — NOT a 0–1 fraction or epoch seconds as old reconstruction
        // assumed.
        let utilization: Double
        let resetTimestamp: String?
        let hasResetTimestampField: Bool

        enum CodingKeys: String, CodingKey {
            case utilization
            case resets_at
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            utilization = try container.decode(Double.self, forKey: .utilization)
            hasResetTimestampField = container.contains(.resets_at)
            resetTimestamp = try container.decodeIfPresent(String.self, forKey: .resets_at)
        }

        /// nil when the reset timestamp can't be parsed — drop just this window.
        func window(label: String) -> UsageWindow? {
            guard hasResetTimestampField else { return nil }
            guard let resetTimestamp else {
                return UsageWindow(label: label, percentConsumed: utilization, resetAt: nil)
            }
            guard let resetAt = Self.parseTimestamp(resetTimestamp) else { return nil }
            return UsageWindow(label: label, percentConsumed: utilization, resetAt: resetAt)
        }

        private static func parseTimestamp(_ string: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            // Fall back for any fractional-second precision (e.g. microseconds)
            // by stripping the fraction, then parsing without it.
            formatter.formatOptions = [.withInternetDateTime]
            let stripped = string.replacingOccurrences(
                of: #"\.\d+"#, with: "", options: .regularExpression)
            return formatter.date(from: stripped)
        }
    }

}
