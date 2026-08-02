//
//  UsageWindow.swift
//  TokenStats
//
//  A normalized, agent-agnostic view of one Usage Window row.
//

import Foundation

/// Stable, presentation-independent identity for one Usage Window.
///
/// Provider labels are not identities: they may be localized, renamed, or
/// synthesized from duration metadata. Keeping that text out of equality,
/// persistence, and SwiftUI IDs lets presentation evolve without changing the
/// underlying reading.
nonisolated enum UsageWindowIdentity: Hashable, Codable, Sendable {
    case shortTerm
    case weekly
    case modelWeekly(model: String)
    case duration(seconds: Int)
    case provider(raw: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case model
        case seconds
        case raw
    }

    private enum Kind: String, Codable {
        case shortTerm
        case weekly
        case modelWeekly
        case duration
        case provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .shortTerm:
            self = .shortTerm
        case .weekly:
            self = .weekly
        case .modelWeekly:
            self = .modelWeekly(model: try container.decode(String.self, forKey: .model))
        case .duration:
            self = .duration(seconds: try container.decode(Int.self, forKey: .seconds))
        case .provider:
            self = .provider(raw: try container.decode(String.self, forKey: .raw))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shortTerm:
            try container.encode(Kind.shortTerm, forKey: .kind)
        case .weekly:
            try container.encode(Kind.weekly, forKey: .kind)
        case .modelWeekly(let model):
            try container.encode(Kind.modelWeekly, forKey: .kind)
            try container.encode(model, forKey: .model)
        case .duration(let seconds):
            try container.encode(Kind.duration, forKey: .kind)
            try container.encode(seconds, forKey: .seconds)
        case .provider(let raw):
            try container.encode(Kind.provider, forKey: .kind)
            try container.encode(raw, forKey: .raw)
        }
    }

    /// English compatibility presentation for old tests and cache diagnostics.
    /// UI code must resolve `localizedTitle(using:)` instead.
    var fallbackTitle: String {
        switch self {
        case .shortTerm:
            return "5-hour"
        case .weekly:
            return "Weekly"
        case .modelWeekly(let model):
            return model
        case .duration(let seconds):
            return Self.durationTitle(seconds: seconds)
        case .provider(let raw):
            return raw
        }
    }

    func localizedTitle(using localizer: AppLocalizer) -> String {
        switch self {
        case .shortTerm:
            return localizer.localized(
                LocalizedStringResource.usageWindowShortTerm
            )
        case .weekly:
            return localizer.localized(
                LocalizedStringResource.usageWindowWeekly
            )
        case .modelWeekly(let model):
            return model
        case .duration(let seconds):
            return Self.localizedDurationTitle(seconds: seconds, locale: localizer.locale)
        case .provider(let raw):
            return raw
        }
    }

    /// Converts a duration reported by an agent into the most specific stable
    /// identity we know. Well-known windows remain stable across old label-only
    /// cache entries and new duration-bearing responses.
    static func reportedDuration(seconds: Int) -> UsageWindowIdentity {
        switch seconds {
        case 5 * 60 * 60:
            return .shortTerm
        case 7 * 24 * 60 * 60:
            return .weekly
        default:
            return .duration(seconds: seconds)
        }
    }

    /// Maps the former persisted `label` field into semantic identity. Unknown
    /// provider text is retained verbatim so a cache migration never discards
    /// an otherwise valid reading.
    static func legacyLabel(_ label: String) -> UsageWindowIdentity {
        switch label {
        case "5-hour":
            return .shortTerm
        case "Weekly":
            return .weekly
        case "Fable":
            return .modelWeekly(model: "Fable")
        default:
            guard let duration = durationSeconds(fromLegacyLabel: label) else {
                return .provider(raw: label)
            }
            return .duration(seconds: duration)
        }
    }

    private static func durationSeconds(fromLegacyLabel label: String) -> Int? {
        let parts = label.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let value = Int(parts[0]),
              value > 0 else {
            return nil
        }

        let multiplier: Int
        switch parts[1] {
        case "day": multiplier = 24 * 60 * 60
        case "hour": multiplier = 60 * 60
        case "minute": multiplier = 60
        case "second": multiplier = 1
        default: return nil
        }
        guard value <= Int.max / multiplier else { return nil }
        return value * multiplier
    }

    private static func durationTitle(seconds: Int) -> String {
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

    private static func localizedDurationTitle(seconds: Int, locale: Locale) -> String {
        let allowedUnit: Set<Duration.UnitsFormatStyle.Unit>
        if seconds.isMultiple(of: 24 * 60 * 60) {
            allowedUnit = [.days]
        } else if seconds.isMultiple(of: 60 * 60) {
            allowedUnit = [.hours]
        } else if seconds.isMultiple(of: 60) {
            allowedUnit = [.minutes]
        } else {
            allowedUnit = [.seconds]
        }
        return Duration.seconds(seconds).formatted(
            .units(
                allowed: allowedUnit,
                width: .wide,
                maximumUnitCount: 1,
                zeroValueUnits: .hide
            )
            .locale(locale)
        )
    }
}

nonisolated struct UsageWindow: Equatable, Codable, Sendable {
    let identity: UsageWindowIdentity
    /// Fraction of the Limit consumed, expressed 0–100.
    let percentConsumed: Double
    /// When this window's usage resets, if the provider exposes it.
    let resetAt: Date?

    init(identity: UsageWindowIdentity, percentConsumed: Double, resetAt: Date?) {
        self.identity = identity
        self.percentConsumed = percentConsumed
        self.resetAt = resetAt
    }

    /// Source-compatible bridge for fixtures and callers that still construct
    /// a reading from the old display label. New production code should supply
    /// `identity` directly.
    init(label: String, percentConsumed: Double, resetAt: Date?) {
        self.identity = .legacyLabel(label)
        self.percentConsumed = percentConsumed
        self.resetAt = resetAt
    }

    /// Temporary English display bridge. This value is derived and is never
    /// encoded, matched, or used as SwiftUI identity.
    var label: String { identity.fallbackTitle }

    /// Fraction of the Limit still available, expressed 0–100.
    var percentRemaining: Double {
        min(max(100 - percentConsumed, 0), 100)
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case label
        case percentConsumed
        case resetAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.identity) {
            identity = try container.decode(UsageWindowIdentity.self, forKey: .identity)
        } else {
            let legacyLabel = try container.decode(String.self, forKey: .label)
            identity = .legacyLabel(legacyLabel)
        }
        percentConsumed = try container.decode(Double.self, forKey: .percentConsumed)
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identity, forKey: .identity)
        try container.encode(percentConsumed, forKey: .percentConsumed)
        try container.encodeIfPresent(resetAt, forKey: .resetAt)
    }
}
