//
//  SessionStore.swift
//  TokenStats
//
//  Read-only reader for the shared agent-sessions SQLite database. The hook
//  plugins (Claude Code / Codex) own the writes; TokenStats only reads, so we
//  open the file read-only and never migrate or mutate it. The path matches the
//  TypeScript side's `resolveDatabasePath()`: $AGENT_SESSIONS_DB, else
//  ~/.local/agent-sessions/sessions.db.
//

import Foundation
import SQLite3

/// Why a read produced no sessions, so the UI can tell "no database yet"
/// (plugins not installed / never run) apart from "database is empty".
enum SessionsReadError: Error {
    /// The database file doesn't exist yet — nothing has written sessions.
    case databaseUnavailable
    /// SQLite returned an error while opening or querying.
    case query(String)
}

/// A value type that resolves the database path and reads the `sessions` table.
/// `load()` is nonisolated and does blocking file I/O, so call it off the main
/// actor (the model wraps it in a detached task).
struct SessionStore: Sendable {
    let path: String

    init(path: String? = nil) {
        self.path = path ?? Self.resolveDatabasePath()
    }

    /// Mirror of the TS `resolveDatabasePath()` so reader and writer agree.
    static func resolveDatabasePath() -> String {
        if let override = ProcessInfo.processInfo.environment["AGENT_SESSIONS_DB"],
           override.isEmpty == false {
            return override
        }
        return realHomeDirectory() + "/.local/agent-sessions/sessions.db"
    }

    /// The user's *real* home directory. Inside the App Sandbox,
    /// `NSHomeDirectory()` points at the container; the shared agent-sessions
    /// data lives in the actual home, which the entitlements' home-relative
    /// exceptions grant access to.
    static func realHomeDirectory() -> String {
        if let passwd = getpwuid(getuid()), let dir = passwd.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    /// Sessions ordered for the popover: needs-you first, then running, then
    /// idle, each newest-updated first. Throws `.databaseUnavailable` when the
    /// file is missing so the caller can show a neutral empty state.
    func load() throws -> [Session] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw SessionsReadError.databaseUnavailable
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "couldn't open database"
            sqlite3_close(db)
            throw SessionsReadError.query(message)
        }
        defer { sqlite3_close(db) }

        // The transcript path isn't a sessions column; it rides along in the
        // hook-event payloads, so pull it from the session's latest event that
        // carries one.
        let sql = """
        SELECT
          s.session_id, s.status, s.agent, s.session_name, s.working_directory,
          s.created_at, s.updated_at,
          (
            SELECT json_extract(e.payload, '$.transcript_path')
            FROM session_events e
            WHERE e.session_id = s.session_id
              AND json_valid(e.payload)
              AND json_extract(e.payload, '$.transcript_path') IS NOT NULL
            ORDER BY e.id DESC
            LIMIT 1
          ) AS transcript_path
        FROM sessions s
        ORDER BY
          CASE s.status
            WHEN 'PENDING_APPROVAL' THEN 0
            WHEN 'RUNNING' THEN 1
            ELSE 2
          END,
          s.updated_at DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SessionsReadError.query(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [Session] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sessionId = text(statement, 0),
                  let rawStatus = text(statement, 1),
                  let status = SessionStatus(rawValue: rawStatus),
                  let agent = text(statement, 2),
                  let name = text(statement, 3),
                  let cwd = text(statement, 4)
            else { continue }

            // Drizzle `mode: "timestamp"` stores whole seconds since the epoch.
            let createdAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 5)))
            let updatedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 6)))

            sessions.append(Session(
                id: sessionId,
                status: status,
                agent: agent,
                name: name,
                workingDirectory: cwd,
                createdAt: createdAt,
                updatedAt: updatedAt,
                transcriptPath: text(statement, 7)
            ))
        }
        return sessions
    }

    /// Reads a TEXT column as a Swift string, or nil when the column is NULL.
    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cString)
    }
}
