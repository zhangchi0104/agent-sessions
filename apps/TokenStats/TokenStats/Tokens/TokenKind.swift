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
nonisolated enum TokenKind: CaseIterable, Hashable, Sendable {
    case directInput
    case output
    case cacheWrite
    case cacheRead

    /// The glossary's name, spelled out. Shown in the column tooltips, since
    /// the headers themselves only have room for an abbreviation.
    var name: String {
        switch self {
        case .directInput: "Direct input"
        case .output: "Output"
        case .cacheWrite: "Cache write"
        case .cacheRead: "Cache read"
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
}
