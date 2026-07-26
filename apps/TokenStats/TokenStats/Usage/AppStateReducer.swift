//
//  AppStateReducer.swift
//  TokenStats
//
//  Pure (state, event) -> state mapping for the UI state machine.
//

import Foundation

enum AppStateReducer {

    static func reduce(state: AppState, event: AppEvent) -> AppState {
        switch event {
        case .fetchSucceeded(let snapshot):
            return .fresh(snapshot)
        case .fetchFailed:
            // Keep showing the last-known snapshot, disclosed as stale. With no
            // snapshot there's nothing to disclose, so stay put.
            switch state {
            case .fresh(let snapshot), .staleDisclosed(let snapshot):
                return .staleDisclosed(snapshot)
            case .signedOut, .loading:
                return state
            }
        case .signedOut:
            return .signedOut
        case .loadingStarted:
            // Only show the bare loading state when we have nothing to display;
            // a refresh over existing data keeps that data visible.
            switch state {
            case .fresh, .staleDisclosed:
                return state
            case .signedOut, .loading:
                return .loading
            }
        }
    }
}

/// Which Coding Agent a piece of state belongs to. Identity only — everything
/// else about an agent is declared by its CodingAgentIntegration, reachable
/// through `integration`.
enum CodingAgentID: String, CaseIterable, Codable, Hashable {
    case claudeCode
    case codex
}

struct CodingAgentStates: Equatable {
    private var states: [CodingAgentID: AppState]

    init(_ states: [CodingAgentID: AppState] = [:]) {
        self.states = states
    }

    subscript(_ id: CodingAgentID) -> AppState {
        get { states[id] ?? .signedOut }
        set { states[id] = newValue }
    }
}

enum CodingAgentEvent: Equatable {
    case signedOut(CodingAgentID)
    case loadingStarted(CodingAgentID)
    case fetchSucceeded(CodingAgentID, UsageSnapshot)
    case fetchFailed(CodingAgentID)
}

enum CodingAgentStateReducer {

    static func reduce(state: CodingAgentStates, event: CodingAgentEvent) -> CodingAgentStates {
        var next = state
        let id: CodingAgentID
        let appEvent: AppEvent

        switch event {
        case .signedOut(let agentID):
            id = agentID
            appEvent = .signedOut
        case .loadingStarted(let agentID):
            id = agentID
            appEvent = .loadingStarted
        case .fetchSucceeded(let agentID, let snapshot):
            id = agentID
            appEvent = .fetchSucceeded(snapshot)
        case .fetchFailed(let agentID):
            id = agentID
            appEvent = .fetchFailed
        }

        next[id] = AppStateReducer.reduce(state: next[id], event: appEvent)
        return next
    }
}
