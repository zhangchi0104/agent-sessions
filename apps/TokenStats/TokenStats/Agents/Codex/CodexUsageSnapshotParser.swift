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
        // Primary → 5-hour Usage Window (the primary gauge), secondary → Weekly.
        // Credits and additional_rate_limits are intentionally ignored for the
        // first Codex UI (see PRD / docs/codex-integration.md).
        return [
            rateLimit.primary_window?.window(label: "5-hour"),
            rateLimit.secondary_window?.window(label: "Weekly"),
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

        func window(label: String) -> UsageWindow {
            // reset_at is Unix epoch seconds; treat absent or non-positive as
            // "reset time unavailable" rather than 1970.
            let resetAt = reset_at.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            return UsageWindow(label: label, percentConsumed: used_percent, resetAt: resetAt)
        }
    }
}
