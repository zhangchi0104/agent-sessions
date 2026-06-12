//
//  Session.swift
//  TokenStats
//
//  A Session is a single Coding Agent conversation/process the user launched
//  (see CONTEXT.md — NOT a billing period, that's a Usage Window). Sessions are
//  written to the shared agent-sessions SQLite database by the hook plugins;
//  TokenStats reads them to show who is RUNNING, who needs the user
//  (PENDING_APPROVAL), and who is IDLE.
//

import Foundation
import SwiftUI

/// The "who are we waiting on?" status of a Session, mirroring the database
/// enum (`IDLE` | `RUNNING` | `PENDING_APPROVAL`).
enum SessionStatus: String, CaseIterable {
    case pendingApproval = "PENDING_APPROVAL"
    case running = "RUNNING"
    case idle = "IDLE"

    /// Short, human-facing label for the popover row.
    var displayName: String {
        switch self {
        case .pendingApproval: return "Needs you"
        case .running: return "Running"
        case .idle: return "Idle"
        }
    }

    /// Surfacing order: sessions needing the user first, then running, then idle.
    var sortPriority: Int {
        switch self {
        case .pendingApproval: return 0
        case .running: return 1
        case .idle: return 2
        }
    }

    /// Status dot color, consistent with the gauge language (attention = warm).
    var color: Color {
        switch self {
        case .pendingApproval: return .orange
        case .running: return .green
        case .idle: return .secondary
        }
    }

    /// Tooltip copy explaining what the status (and its dot color) means,
    /// for first-timers who haven't learned the color language yet.
    var helpText: String {
        switch self {
        case .pendingApproval: return "The agent is waiting on your approval or input"
        case .running: return "The agent is working"
        case .idle: return "Waiting for your next prompt"
        }
    }
}

/// One Session row as read from the database.
struct Session: Identifiable, Equatable {
    /// The agent-assigned session id (stable across events); used as identity.
    let id: String
    let status: SessionStatus
    /// Source Coding Agent, e.g. "ClaudeCode", "Codex", "OpenCode".
    let agent: String
    let name: String
    let workingDirectory: String
    let createdAt: Date
    let updatedAt: Date
    /// Path to the agent's transcript file (from the session's hook events);
    /// nil when no event carried one.
    let transcriptPath: String?
    /// Token totals parsed from the transcript. Filled in by SessionsModel
    /// after the database read; nil when no transcript/usage is available.
    var tokenUsage: TokenUsage? = nil

    /// Row title. The hook CLIs fall back to the session id when no name was
    /// given, so a UUID-shaped (or empty) `name` is replaced with the working
    /// directory's last path component — far more recognisable than hex.
    var displayName: String {
        guard name.isEmpty || Self.looksLikeSessionID(name) else { return name }
        let directoryName = (workingDirectory as NSString).lastPathComponent
        return directoryName.isEmpty ? name : directoryName
    }

    /// UUID-ish heuristic: only hex digits and dashes, 32–36 characters
    /// (covers canonical UUIDs and dash-stripped variants).
    private static func looksLikeSessionID(_ value: String) -> Bool {
        guard (32...36).contains(value.count) else { return false }
        return value.allSatisfy { $0 == "-" || $0.isHexDigit }
    }

    /// Working directory with the home prefix collapsed to `~` for compactness.
    var displayDirectory: String {
        let home = SessionStore.realHomeDirectory()
        if workingDirectory == home { return "~" }
        if workingDirectory.hasPrefix(home + "/") {
            return "~" + workingDirectory.dropFirst(home.count)
        }
        return workingDirectory
    }
}
