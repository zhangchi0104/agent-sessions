//
//  InMemoryUserDefaults.swift
//  TokenStats
//
//  Process-only defaults for tests. UserDefaults has no public in-memory
//  initializer, so this subclass keeps every read and write in a locked map
//  and never forwards mutations to CFPreferences.
//

import Foundation

nonisolated final class InMemoryUserDefaults: UserDefaults {
    let backingSuiteName: String

    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var registeredValues: [String: Any] = [:]

    init(
        identifier: UUID = UUID(),
        initialValues: [String: Any] = [:]
    ) {
        backingSuiteName = "dev.otakuma.TokenStats.in-memory.\(identifier.uuidString)"
        values = initialValues
        // The identifier is always a valid, unique suite name. All accessors
        // below are overridden, so the suite supplies class identity only and
        // is never written to disk.
        super.init(suiteName: backingSuiteName)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock {
            values[defaultName] ?? registeredValues[defaultName]
        }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock {
            values[defaultName] = value
        }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock {
            _ = values.removeValue(forKey: defaultName)
        }
    }

    override func register(defaults registrationDictionary: [String: Any]) {
        lock.withLock {
            registeredValues.merge(registrationDictionary) { current, _ in current }
        }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.withLock {
            registeredValues.merging(values) { _, value in value }
        }
    }

    override func synchronize() -> Bool {
        true
    }
}
