//
//  ModelName.swift
//  TokenStats
//
//  The Token Odometer's second axis (CONTEXT.md): the Model a Coding Agent
//  reported against the tokens it consumed.
//

import Foundation

/// Which Model a bucket of usage belongs to — the name the transcript gave it,
/// or `unattributed` when no line in the file ever named one.
///
/// A case rather than a reserved string. `"unknown"` as a sentinel cannot be
/// told apart from a Model a transcript genuinely calls `unknown`, and the row
/// is supposed to mean exactly what it says: nothing here named a Model. The
/// word only reappears at the edge, where the table needs something to print.
nonisolated enum ModelName: Hashable, Sendable {
    case named(String)
    case unattributed

    /// What the table shows for this Model.
    var displayName: String {
        switch self {
        case .named(let name): name
        case .unattributed: "unknown"
        }
    }
}

nonisolated extension ModelName: Comparable {
    /// Ordered by what the reader sees, so a tie-break between two Models with
    /// equal totals is alphabetical on screen rather than by case order.
    static func < (lhs: ModelName, rhs: ModelName) -> Bool {
        lhs.displayName < rhs.displayName
    }
}
