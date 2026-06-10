//
//  LastKnownUsageStore.swift
//  TokenStats
//
//  UserDefaults persistence of the last snapshot, so launch shows something
//  meaningful immediately (disclosed as stale by its true age) instead of an
//  empty state (PRD).
//

import Foundation

struct LastKnownUsageStore {
    private let defaults: UserDefaults
    private let legacyKey = "lastKnownUsageSnapshot"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ snapshot: UsageSnapshot) {
        save(snapshot, for: .claudeCode)
    }

    func save(_ snapshot: UsageSnapshot, for agentID: CodingAgentID) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(for: agentID))
    }

    func load() -> UsageSnapshot? {
        load(for: .claudeCode)
    }

    func load(for agentID: CodingAgentID) -> UsageSnapshot? {
        let data = defaults.data(forKey: key(for: agentID))
            ?? legacyData(for: agentID)
        guard let data else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    func clear() {
        clear(for: .claudeCode)
    }

    func clear(for agentID: CodingAgentID) {
        defaults.removeObject(forKey: key(for: agentID))
        if agentID == .claudeCode {
            defaults.removeObject(forKey: legacyKey)
        }
    }

    private func key(for agentID: CodingAgentID) -> String {
        "\(legacyKey).\(agentID.rawValue)"
    }

    private func legacyData(for agentID: CodingAgentID) -> Data? {
        guard agentID == .claudeCode else { return nil }
        return defaults.data(forKey: legacyKey)
    }
}
