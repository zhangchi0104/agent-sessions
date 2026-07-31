//
//  CodexUsageSnapshotParser.swift
//  TokenStats
//
//  Pure: raw Codex usage JSON (the `RateLimitStatusPayload` from
//  GET /backend-api/wham/usage, see docs/codex-integration.md and ADR-0002) →
//  normalized [UsageWindow]. Mirrors UsageSnapshotParser but for Codex's
//  encoding, which differs from Claude Code's: `used_percent` is an integer
//  percent and `reset_at` is Unix epoch seconds (not an ISO-8601 string).
//

import Foundation

enum CodexUsageSnapshotParser {

    static func parse(_ data: Data) throws -> [UsageWindow] {
        let payload = try JSONDecoder().decode(RateLimitStatusPayload.self, from: data)
        guard let rateLimit = payload.rate_limit else { return [] }
        // A window's duration is authoritative when present. Codex currently
        // moves the weekly window between these slots, so slot position alone
        // cannot name it. The fallback labels retain compatibility with older
        // payloads that omitted every duration field.
        //
        // Credits and additional_rate_limits are intentionally ignored for the
        // first Codex UI (see PRD / docs/codex-integration.md).
        return [
            rateLimit.primary_window?.window(fallbackLabel: "5-hour"),
            rateLimit.secondary_window?.window(fallbackLabel: "Weekly"),
        ].compactMap { $0 }
    }

    private struct RateLimitStatusPayload: Decodable {
        let rate_limit: RateLimit?

        enum CodingKeys: String, CodingKey { case rate_limit }

        init(from decoder: Decoder) throws {
            // A present-but-malformed `rate_limit` must not sink the whole
            // payload — decode it independently.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rate_limit = try? container.decodeIfPresent(RateLimit.self, forKey: .rate_limit)
        }
    }

    private struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?

        enum CodingKeys: String, CodingKey { case primary_window, secondary_window }

        init(from decoder: Decoder) throws {
            // Decode each window independently so one broken block doesn't drop
            // the other.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            primary_window = try? container.decodeIfPresent(Window.self, forKey: .primary_window)
            secondary_window = try? container.decodeIfPresent(Window.self, forKey: .secondary_window)
        }
    }

    private struct Window: Decodable {
        let used_percent: Double
        let reset_at: Double?
        let limit_window_seconds: Double?
        let window_seconds: Double?
        let window_minutes: Double?

        private enum CodingKeys: String, CodingKey {
            case used_percent, reset_at
            case limit_window_seconds, window_seconds, window_minutes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            used_percent = try container.decode(Double.self, forKey: .used_percent)
            reset_at = try container.decodeIfPresent(Double.self, forKey: .reset_at)
            // A malformed optional duration must not discard an otherwise
            // usable reading; the slot fallback remains available.
            limit_window_seconds = try? container.decodeIfPresent(
                Double.self, forKey: .limit_window_seconds)
            window_seconds = try? container.decodeIfPresent(Double.self, forKey: .window_seconds)
            window_minutes = try? container.decodeIfPresent(Double.self, forKey: .window_minutes)
        }

        func window(fallbackLabel: String) -> UsageWindow {
            // reset_at is Unix epoch seconds; treat absent or non-positive as
            // "reset time unavailable" rather than 1970.
            let resetAt = reset_at.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            let label = if let durationSeconds {
                Self.label(forDurationSeconds: durationSeconds)
            } else {
                fallbackLabel
            }
            return UsageWindow(label: label, percentConsumed: used_percent, resetAt: resetAt)
        }

        /// Codex has used all three names across its standalone payload and
        /// rate-limit surfaces. Prefer the documented standalone field, while
        /// accepting the older aliases used by the Windows implementation.
        private var durationSeconds: Int? {
            if let seconds = positiveInteger(limit_window_seconds)
                ?? positiveInteger(window_seconds) {
                return seconds
            }
            guard let minutes = positiveInteger(window_minutes),
                  minutes <= Int.max / 60 else {
                return nil
            }
            return minutes * 60
        }

        private func positiveInteger(_ value: Double?) -> Int? {
            guard let value,
                  value.isFinite,
                  value >= 1,
                  value <= Double(Int.max) else {
                return nil
            }
            return Int(value.rounded(.towardZero))
        }

        private static func label(forDurationSeconds seconds: Int) -> String {
            if seconds == 7 * 24 * 60 * 60 {
                return "Weekly"
            }
            if seconds.isMultiple(of: 24 * 60 * 60) {
                return "\(seconds / (24 * 60 * 60))-day"
            }
            if seconds.isMultiple(of: 60 * 60) {
                return "\(seconds / (60 * 60))-hour"
            }
            if seconds.isMultiple(of: 60) {
                return "\(seconds / 60)-minute"
            }
            return "\(seconds)-second"
        }
    }
}
