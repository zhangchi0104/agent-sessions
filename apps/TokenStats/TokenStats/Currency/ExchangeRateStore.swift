//
//  ExchangeRateStore.swift
//  TokenStats
//
//  Versioned UserDefaults persistence for a small full-table cache, the
//  user's presentation choice, and the durable 24-hour attempt gate.
//

import Foundation

nonisolated struct ExchangeRateStore {
    private enum Key {
        static let snapshot = "currency.exchangeRateSnapshot.v1"
        static let selection = "currency.displaySelection.v1"
        static let attempt = "currency.exchangeRateAttempt.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSnapshot() -> ExchangeRateSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshot),
              let snapshot = try? JSONDecoder().decode(ExchangeRateSnapshot.self, from: data),
              snapshot.isValidEnvelope
        else { return nil }
        return snapshot
    }

    func saveSnapshot(_ snapshot: ExchangeRateSnapshot) {
        guard snapshot.isValidEnvelope,
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: Key.snapshot)
    }

    func loadSelection() -> DisplayCurrencySelection {
        guard let data = defaults.data(forKey: Key.selection),
              let selection = try? JSONDecoder().decode(DisplayCurrencySelection.self, from: data)
        else {
            // A damaged preference has the same safe behavior as a missing one,
            // and rewriting it prevents every launch from reparsing bad data.
            saveSelection(.system)
            return .system
        }
        return selection
    }

    func saveSelection(_ selection: DisplayCurrencySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Key.selection)
    }

    func loadAttempt() -> ExchangeRateAttempt? {
        guard let data = defaults.data(forKey: Key.attempt) else { return nil }
        return try? JSONDecoder().decode(ExchangeRateAttempt.self, from: data)
    }

    func saveAttempt(_ attempt: ExchangeRateAttempt) {
        guard let data = try? JSONEncoder().encode(attempt) else { return }
        defaults.set(data, forKey: Key.attempt)
    }
}
