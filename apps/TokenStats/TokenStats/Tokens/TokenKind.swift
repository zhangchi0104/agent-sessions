//
//  TokenKind.swift
//  TokenStats
//
//  The Token Odometer's third axis (CONTEXT.md): the four disjoint ways a
//  token is counted against a request. A total is their sum and no token is
//  counted twice. It lives beside TokenUsage rather than with the table that
//  draws it — the axis is domain vocabulary, and the table is one reader of it.
//

import Foundation

/// One of the four Token Kinds, in the order the table's columns and the
/// segments of its proportion bar both run — which is what lets the column
/// header double as the colour key.
nonisolated enum TokenKind: String, CaseIterable, Codable, Hashable, Sendable {
    case directInput
    case output
    case cacheWrite
    case cacheRead

    /// The glossary's name, spelled out. Shown in the column tooltips, since
    /// the headers themselves only have room for an abbreviation.
    var name: LocalizedStringResource {
        switch self {
        case .directInput:
            LocalizedStringResource.tokensKindDirectInput
        case .output:
            LocalizedStringResource.tokensKindOutput
        case .cacheWrite:
            LocalizedStringResource.tokensKindCacheWrite
        case .cacheRead:
            LocalizedStringResource.tokensKindCacheRead
        }
    }
}

nonisolated extension TokenUsage {
    /// This usage's figure for one Token Kind. It reads off `TokenUsage`
    /// because that is whose data it is; asking the kind to reach in here
    /// instead would put four of these fields in a type that owns none of them.
    func amount(of kind: TokenKind) -> Int {
        switch kind {
        case .directInput: inputTokens
        case .output: outputTokens
        case .cacheWrite: cacheCreationTokens
        case .cacheRead: cacheReadTokens
        }
    }

    /// The table projection produced by the enabled Token Kind headings. This
    /// deliberately does not replace `totalTokens`: the latter remains the raw
    /// four-kind Token Odometer, while this figure drives only table subtotals,
    /// ordering, composition percentages, and the filtered proportion bar.
    func selectedTotal(_ selection: Set<TokenKind>) -> Int {
        selection.reduce(into: 0) { total, kind in
            total += amount(of: kind)
        }
    }

    /// The objective token summary shared with Windows: direct input, cache
    /// writes, and output. Cache reads stay in the raw Odometer and table but
    /// are excluded from this specifically named presentation.
    var billingTokens: Int {
        inputTokens + cacheCreationTokens + outputTokens
    }
}

/// Pure Token Kind cell formatting, shared by the table and its regression
/// tests. Percentages are composition within the row's selected kinds, never a
/// Usage Window or quota percentage.
nonisolated enum TokenValueFormatting {
    static func cell(
        amount: Int,
        selectedTotal: Int,
        isSelected: Bool,
        mode: TokenValueDisplayMode,
        locale: Locale
    ) -> String {
        guard amount > 0 else { return "–" }
        let value = TokenUsage.compact(amount, locale: locale)
        guard isSelected else { return value }
        let percentage = compositionPercentage(amount: amount, total: selectedTotal, locale: locale)
        switch mode {
        case .value: return value
        case .percentage: return percentage
        case .valueAndPercentage: return "\(value)\n(\(percentage))"
        }
    }

    static func compositionPercentage(
        amount: Int,
        total: Int,
        locale: Locale
    ) -> String {
        guard total > 0 else { return "–" }
        let fraction = Double(amount) / Double(total)
        return fraction.formatted(
            .percent
                .precision(.fractionLength(0...1))
                .locale(locale)
        )
    }
}
