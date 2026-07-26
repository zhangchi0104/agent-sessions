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
            raw.fableWeekly?.window(label: "Fable"),
        ].compactMap { $0 }
        return meteredWindows
    }

    private struct RawSnapshot: Decodable {
        let five_hour: RawWindow?
        let seven_day: RawWindow?
        /// Per-model weekly quotas ride in this generic array rather than in a
        /// top-level `seven_day_<model>` block (Claude Code renders them as
        /// "Current week (<model>)").
        let limits: [RawScopedLimit]?

        /// Fable's weekly quota: the model-scoped weekly entry whose model
        /// display name mentions Fable (e.g. "Fable 5").
        var fableWeekly: RawScopedLimit? {
            limits?.first {
                $0.kind == "weekly_scoped"
                    && $0.modelDisplayName?.localizedCaseInsensitiveContains("fable") == true
            }
        }

        enum CodingKeys: String, CodingKey {
            case five_hour, seven_day, limits
        }

        init(from decoder: Decoder) throws {
            // A present-but-malformed block (e.g. missing resets_at) must not
            // sink the whole snapshot — decode each window independently.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            five_hour = try? container.decodeIfPresent(RawWindow.self, forKey: .five_hour)
            seven_day = try? container.decodeIfPresent(RawWindow.self, forKey: .seven_day)
            limits = try? container.decodeIfPresent([RawScopedLimit].self, forKey: .limits)
        }
    }

    /// One entry of the `limits` array. Every field is optional so an entry of a
    /// shape we don't recognize reads as "not the limit we're looking for"
    /// instead of failing the whole array's decode.
    private struct RawScopedLimit: Decodable {
        let kind: String?
        /// Percent consumed (0–100), same encoding as a window's `utilization`.
        let percent: Double?
        let resets_at: String?
        let scope: Scope?

        var modelDisplayName: String? { scope?.model?.display_name }

        struct Scope: Decodable {
            let model: Model?

            struct Model: Decodable {
                let display_name: String?
            }
        }

        /// Same rules as a top-level window: an explicit null reset time keeps
        /// the window with unknown timing, an unparseable one drops it.
        func window(label: String) -> UsageWindow? {
            guard let percent else { return nil }
            guard let resets_at else {
                return UsageWindow(label: label, percentConsumed: percent, resetAt: nil)
            }
            guard let resetAt = UsageSnapshotParser.parseTimestamp(resets_at) else { return nil }
            return UsageWindow(label: label, percentConsumed: percent, resetAt: resetAt)
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
            guard let resetAt = UsageSnapshotParser.parseTimestamp(resetTimestamp) else { return nil }
            return UsageWindow(label: label, percentConsumed: utilization, resetAt: resetAt)
        }
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
