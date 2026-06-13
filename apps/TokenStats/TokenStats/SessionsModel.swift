//
//  SessionsModel.swift
//  TokenStats
//
//  Owns the Sessions tab's state. The database is written by external hook
//  processes, so there's nothing to subscribe to — the model re-reads on a
//  short interval while the popover's Sessions tab is visible (see
//  `pollWhileVisible`) and the view drives that via a cancellable `.task`.
//

import Foundation
import Observation

/// What the Sessions tab should render. Distinguishes "no database yet" (plugins
/// not installed / never run) from "database is empty" so the empty state can be
/// honest about which it is.
enum SessionsLoadState: Equatable, Sendable {
    /// First read hasn't completed yet.
    case loading
    /// A successful read; may be an empty array (no sessions recorded).
    case loaded([Session])
    /// The database file doesn't exist yet.
    case unavailable
    /// A read error; carries a short detail for diagnostics.
    case failed(String)
}

@MainActor
@Observable
final class SessionsModel {
    private(set) var state: SessionsLoadState = .loading

    private let store: SessionStore
    private let tokenReader: TranscriptTokenReader

    init(store: SessionStore = SessionStore(),
         tokenReader: TranscriptTokenReader = TranscriptTokenReader()) {
        self.store = store
        self.tokenReader = tokenReader
    }

    /// Re-read the database once. Keeps the previous state on-screen until the
    /// new read lands, so polling never flashes a loading spinner.
    func refresh() async {
        let store = self.store
        var outcome: SessionsLoadState = await Task.detached {
            do {
                return .loaded(try store.load())
            } catch SessionsReadError.databaseUnavailable {
                return .unavailable
            } catch let SessionsReadError.query(message) {
                return .failed(message)
            } catch {
                return .failed(String(describing: error))
            }
        }.value

        // Enrich with token totals from each session's transcript. The reader
        // caches per-file parse progress, so steady-state polling only pays
        // for newly appended transcript bytes.
        if case .loaded(var sessions) = outcome {
            for index in sessions.indices {
                if let path = sessions[index].transcriptPath {
                    sessions[index].tokenUsage = await tokenReader.usage(forTranscriptAt: path)
                }
            }
            outcome = .loaded(sessions)
        }
        state = outcome
    }

    /// Refresh immediately, then keep refreshing until cancelled. Drive from a
    /// SwiftUI `.task`, which cancels this loop when the tab disappears.
    func pollWhileVisible(interval: Duration = .seconds(4)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }
}
