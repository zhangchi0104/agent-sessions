//
//  ExchangeRateStore.swift
//  TokenStats
//
//  Versioned UserDefaults persistence for display selection and one atomic
//  exchange-rate state containing source preferences, last-known-good rates,
//  and the durable rolling-24-hour attempt gate.
//

import Foundation

nonisolated struct ExchangeRatePersistentState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var sourcePreferences: ExchangeRateSourcePreferences
    var snapshot: ExchangeRateSnapshot?
    var attempt: ExchangeRateAttempt?

    static let empty = ExchangeRatePersistentState(
        schemaVersion: currentSchemaVersion,
        sourcePreferences: .default,
        snapshot: nil,
        attempt: nil
    )

    var isValidEnvelope: Bool {
        let activeSource = sourcePreferences.activeSource
        return schemaVersion == Self.currentSchemaVersion
            && sourcePreferences == sourcePreferences.sanitized()
            && (snapshot == nil || (
                snapshot?.isValidEnvelope == true
                    && snapshot?.source == activeSource
            ))
            && (attempt == nil || attempt?.source == activeSource)
    }
}

nonisolated struct ExchangeRateStore {
    private enum Key {
        static let persistentState = "currency.exchangeRateState.v2"
        static let legacySnapshot = "currency.exchangeRateSnapshot.v1"
        static let selection = "currency.displaySelection.v2"
        static let legacySelection = "currency.displaySelection.v1"
        static let legacyAttempt = "currency.exchangeRateAttempt.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPersistentState() -> ExchangeRatePersistentState {
        if let data = defaults.data(forKey: Key.persistentState) {
            guard let state = try? JSONDecoder().decode(
                ExchangeRatePersistentState.self,
                from: data
            ), state.isValidEnvelope else {
                let repaired = ExchangeRatePersistentState.empty
                savePersistentState(repaired)
                return repaired
            }
            return state
        }

        let migrated = migrateLegacyState()
        savePersistentState(migrated)
        return migrated
    }

    func savePersistentState(_ state: ExchangeRatePersistentState) {
        guard state.isValidEnvelope,
              let data = try? JSONEncoder().encode(state)
        else { return }
        defaults.set(data, forKey: Key.persistentState)
    }

    func loadSnapshot() -> ExchangeRateSnapshot? {
        loadPersistentState().snapshot
    }

    func saveSnapshot(_ snapshot: ExchangeRateSnapshot) {
        guard snapshot.isValidEnvelope else { return }
        var state = loadPersistentState()
        state.sourcePreferences.activate(snapshot.source)
        state.snapshot = snapshot
        if state.attempt?.source != snapshot.source {
            state.attempt = nil
        }
        savePersistentState(state)
    }

    func loadSelection() -> DisplayCurrencySelection {
        if let data = defaults.data(forKey: Key.selection) {
            guard let selection = try? JSONDecoder().decode(
                DisplayCurrencySelection.self,
                from: data
            ) else {
                return repairSelectionToUSD()
            }
            return selection
        }

        if let legacyData = defaults.data(forKey: Key.legacySelection) {
            guard let legacySelection = try? JSONDecoder().decode(
                DisplayCurrencySelection.self,
                from: legacyData
            ) else {
                return repairSelectionToUSD()
            }

            // v1 wrote System Region even when the user had never made a
            // choice. Preserve an explicit fixed currency, while migrating
            // that old implicit default to the new fixed-USD default.
            let migrated: DisplayCurrencySelection
            switch legacySelection {
            case .system:
                migrated = .fixed(.usd)
            case .fixed:
                migrated = legacySelection
            }
            saveSelection(migrated)
            return migrated
        }

        return repairSelectionToUSD()
    }

    func saveSelection(_ selection: DisplayCurrencySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Key.selection)
    }

    private func repairSelectionToUSD() -> DisplayCurrencySelection {
        // A damaged preference has the same safe behavior as a missing one,
        // and rewriting it prevents every launch from reparsing bad data.
        let fallback = DisplayCurrencySelection.fixed(.usd)
        saveSelection(fallback)
        return fallback
    }

    func loadAttempt() -> ExchangeRateAttempt? {
        loadPersistentState().attempt
    }

    func saveAttempt(_ attempt: ExchangeRateAttempt) {
        guard attempt.source.isValid else { return }
        var state = loadPersistentState()
        state.sourcePreferences.activate(attempt.source)
        if state.snapshot?.source != attempt.source {
            state.snapshot = nil
        }
        state.attempt = attempt
        savePersistentState(state)
    }

    func loadSourcePreferences() -> ExchangeRateSourcePreferences {
        loadPersistentState().sourcePreferences
    }

    private func migrateLegacyState() -> ExchangeRatePersistentState {
        let source = ExchangeRateSource.default
        let snapshot: ExchangeRateSnapshot?
        if let data = defaults.data(forKey: Key.legacySnapshot),
           let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            let candidate = ExchangeRateSnapshot(
                source: source,
                fetchedAt: legacy.fetchedAt,
                quotes: legacy.quotes
            )
            snapshot = candidate.isValidEnvelope ? candidate : nil
        } else {
            snapshot = nil
        }

        let attempt: ExchangeRateAttempt?
        if let data = defaults.data(forKey: Key.legacyAttempt),
           let legacy = try? JSONDecoder().decode(LegacyAttempt.self, from: data) {
            attempt = ExchangeRateAttempt(
                attemptedAt: legacy.attemptedAt,
                outcome: legacy.outcome,
                errorDescription: legacy.errorDescription,
                source: source
            )
        } else {
            attempt = nil
        }

        return ExchangeRatePersistentState(
            schemaVersion: ExchangeRatePersistentState.currentSchemaVersion,
            sourcePreferences: .default,
            snapshot: snapshot,
            attempt: attempt
        )
    }

    private struct LegacySnapshot: Decodable {
        let schemaVersion: Int
        let baseCode: CurrencyCode
        let fetchedAt: Date
        let quotes: [ExchangeRateQuote]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            baseCode = try container.decode(CurrencyCode.self, forKey: .baseCode)
            fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
            quotes = try container.decode([ExchangeRateQuote].self, forKey: .quotes)
            guard schemaVersion == 1, baseCode == .usd else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported legacy exchange-rate snapshot"
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, baseCode, fetchedAt, quotes
        }
    }

    private struct LegacyAttempt: Decodable {
        let attemptedAt: Date
        let outcome: ExchangeRateAttemptOutcome
        let errorDescription: String?
    }
}
