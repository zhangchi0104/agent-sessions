//
//  CurrencyModelTests.swift
//  TokenStatsTests
//

import AppKit
import Foundation
import Testing
@testable import TokenStats

// These lifecycle tests intentionally post process-wide AppKit notifications.
// Serialize the suite so one model cannot refresh in response to another
// test's activation or wake event.
@Suite(.serialized)
@MainActor
struct CurrencyModelTests {
    @Test func sourceValidationRequiresCredentialFreeHTTPSAndCanonicalizesHost() throws {
        #expect(throws: ExchangeRateSourceError.httpsRequired) {
            try ExchangeRateSource.validated(
                providerID: .frankfurter,
                endpointText: "http://api.frankfurter.dev/v2/rates?base=USD"
            )
        }
        #expect(throws: ExchangeRateSourceError.credentialsNotAllowed) {
            try ExchangeRateSource.validated(
                providerID: .frankfurter,
                endpointText: "https://user:password@api.frankfurter.dev/v2/rates"
            )
        }
        #expect(throws: ExchangeRateSourceError.credentialsNotAllowed) {
            try ExchangeRateSource.validated(
                providerID: .exchangeRateAPI,
                endpointText: "https://rates.example.test/latest/USD?api_key=secret"
            )
        }
        for providerID in ExchangeRateProviderID.allCases {
            for host in ["v6.exchangerate-api.com", "v6.exchangerate-api.com."] {
                #expect(throws: ExchangeRateSourceError.credentialsNotAllowed) {
                    try ExchangeRateSource.validated(
                        providerID: providerID,
                        endpointText: "https://\(host)/v6/not-a-real-key/latest/USD"
                    )
                }
            }
        }
        #expect(throws: ExchangeRateSourceError.fragmentNotAllowed) {
            try ExchangeRateSource.validated(
                providerID: .frankfurter,
                endpointText: "https://api.frankfurter.dev/v2/rates#latest"
            )
        }

        let source = try ExchangeRateSource.validated(
            providerID: .frankfurter,
            endpointText: "  HTTPS://API.FRANKFURTER.DEV./v2/rates?base=USD  "
        )
        #expect(source.endpoint.scheme == "https")
        #expect(source.endpoint.host == "api.frankfurter.dev")
        #expect(source.endpoint.absoluteString
                == "https://api.frankfurter.dev/v2/rates?base=USD")
    }

    @Test func sourcePreferencesRememberEachOverrideAndRestoreDefaultsIndependently() {
        let frankfurterOverride = customSource(.frankfurter, suffix: "mirror/frankfurter")
        let exchangeRateAPIOverride = customSource(.exchangeRateAPI, suffix: "mirror/open")
        let ecbOverride = customSource(.ecb, suffix: "mirror/ecb")
        var preferences = ExchangeRateSourcePreferences.default

        preferences.activate(frankfurterOverride)
        preferences.activate(exchangeRateAPIOverride)
        preferences.activate(ecbOverride)

        #expect(preferences.selectedProviderID == .ecb)
        #expect(preferences.source(for: .frankfurter) == frankfurterOverride)
        #expect(preferences.source(for: .exchangeRateAPI) == exchangeRateAPIOverride)
        #expect(preferences.source(for: .ecb) == ecbOverride)

        preferences.activate(defaultSource(.exchangeRateAPI))

        #expect(preferences.selectedProviderID == .exchangeRateAPI)
        #expect(preferences.source(for: .frankfurter) == frankfurterOverride)
        #expect(preferences.source(for: .exchangeRateAPI) == defaultSource(.exchangeRateAPI))
        #expect(preferences.source(for: .ecb) == ecbOverride)

        preferences.activate(defaultSource(.frankfurter))
        #expect(preferences.source(for: .frankfurter) == defaultSource(.frankfurter))
        #expect(preferences.source(for: .ecb) == ecbOverride)
    }

    @Test func legacyFrankfurterCacheMigratesToSourceStampedState() throws {
        let defaults = try makeDefaults()
        let fetchedAt = Date(timeIntervalSince1970: 101)
        let attemptedAt = Date(timeIntervalSince1970: 202)
        defaults.set(
            try JSONEncoder().encode(LegacySnapshotFixture(
                schemaVersion: 1,
                baseCode: .usd,
                fetchedAt: fetchedAt,
                quotes: [quote("CNY", rate: "7.1")]
            )),
            forKey: "currency.exchangeRateSnapshot.v1"
        )
        defaults.set(
            try JSONEncoder().encode(LegacyAttemptFixture(
                attemptedAt: attemptedAt,
                outcome: .success,
                errorDescription: nil
            )),
            forKey: "currency.exchangeRateAttempt.v1"
        )

        let store = ExchangeRateStore(defaults: defaults)
        let state = store.loadPersistentState()

        #expect(state.schemaVersion == ExchangeRatePersistentState.currentSchemaVersion)
        #expect(state.sourcePreferences == .default)
        #expect(state.snapshot?.schemaVersion == ExchangeRateSnapshot.currentSchemaVersion)
        #expect(state.snapshot?.source == .default)
        #expect(state.snapshot?.fetchedAt == fetchedAt)
        #expect(state.snapshot?.quote(for: code("CNY"))?.rate == Decimal(string: "7.1"))
        #expect(state.attempt?.source == .default)
        #expect(state.attempt?.attemptedAt == attemptedAt)
        #expect(state.attempt?.outcome == .success)
        #expect(defaults.data(forKey: "currency.exchangeRateState.v2") != nil)
    }

    @Test func damagedPersistentStateRepairsToSafeDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: "currency.exchangeRateState.v2")
        let store = ExchangeRateStore(defaults: defaults)

        let repaired = store.loadPersistentState()

        #expect(repaired == .empty)
        #expect(store.loadPersistentState() == .empty)
        #expect(store.loadSourcePreferences() == .default)
        #expect(store.loadSnapshot() == nil)
        #expect(store.loadAttempt() == nil)
    }

    @Test func missingAndDamagedPreferencesDefaultToFixedUSD() throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        #expect(store.loadSelection() == .fixed(.usd))
        #expect(defaults.data(forKey: "currency.displaySelection.v2") != nil)

        defaults.set(Data("not-json".utf8), forKey: "currency.displaySelection.v2")
        #expect(store.loadSelection() == .fixed(.usd))
        let model = CurrencyModel(
            provider: RateProviderStub(responses: []),
            store: store,
            locale: { Locale(identifier: "zh_CN") },
            schedulesAutomaticRefresh: false
        )

        #expect(model.selection == .fixed(.usd))
        #expect(model.requestedCurrencyCode == .usd)
        #expect(model.systemCurrencyCode == code("CNY"))
        #expect(model.displayContext.currencyCode == .usd)
        #expect(!model.displayContext.isFallback)
    }

    @Test func legacyDefaultMigratesToUSDWhileFixedChoicesSurvive() throws {
        let systemDefaults = try makeDefaults()
        systemDefaults.set(
            try JSONEncoder().encode(DisplayCurrencySelection.system),
            forKey: "currency.displaySelection.v1"
        )
        let systemStore = ExchangeRateStore(defaults: systemDefaults)

        #expect(systemStore.loadSelection() == .fixed(.usd))
        #expect(systemDefaults.data(forKey: "currency.displaySelection.v2") != nil)

        let fixedDefaults = try makeDefaults()
        fixedDefaults.set(
            try JSONEncoder().encode(DisplayCurrencySelection.fixed(code("CNY"))),
            forKey: "currency.displaySelection.v1"
        )
        let fixedStore = ExchangeRateStore(defaults: fixedDefaults)

        #expect(fixedStore.loadSelection() == .fixed(code("CNY")))

        fixedStore.saveSelection(.system)
        #expect(fixedStore.loadSelection() == .system)
    }

    @Test func snapshotSelectionAndAttemptRoundTrip() throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let snapshot = ExchangeRateSnapshot(
            fetchedAt: fetchedAt,
            quotes: [quote("CNY", rate: "7.1")]
        )
        let attempt = ExchangeRateAttempt(
            attemptedAt: fetchedAt,
            outcome: .success,
            errorDescription: nil
        )

        store.saveSnapshot(snapshot)
        store.saveSelection(.fixed(code("CNY")))
        store.saveAttempt(attempt)

        #expect(store.loadSnapshot() == snapshot)
        #expect(store.loadSelection() == .fixed(code("CNY")))
        #expect(store.loadAttempt() == attempt)
    }

    @Test func successfulSourceValidationAtomicallyReplacesStateAndRestartsDailyGate() async throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        let clock = CurrencyTestClock(Date(timeIntervalSince1970: 300_000))
        let oldSnapshot = ExchangeRateSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 100),
            quotes: [quote("CNY", rate: "7.0")]
        )
        let oldAttempt = ExchangeRateAttempt(
            attemptedAt: Date(timeIntervalSince1970: 200),
            outcome: .success,
            errorDescription: nil
        )
        store.savePersistentState(ExchangeRatePersistentState(
            schemaVersion: ExchangeRatePersistentState.currentSchemaVersion,
            sourcePreferences: .default,
            snapshot: oldSnapshot,
            attempt: oldAttempt
        ))
        let candidate = customSource(.exchangeRateAPI, suffix: "rates/latest/USD")
        let provider = RateProviderStub(
            responses: [.success([quote("JPY", rate: "151")])],
            delay: .milliseconds(100)
        )
        let model = CurrencyModel(
            provider: provider,
            store: store,
            now: { clock.value },
            schedulesAutomaticRefresh: false
        )

        let validation = Task {
            await model.validateAndActivateSource(
                providerID: candidate.providerID,
                endpointText: candidate.endpoint.absoluteString
            )
        }
        try await waitForRequests(1, from: provider)

        #expect(model.isValidatingSource)
        #expect(model.activeSource == .default)
        #expect(model.snapshot == oldSnapshot)
        #expect(model.lastAttempt == oldAttempt)

        #expect(await validation.value)
        #expect(!model.isValidatingSource)
        #expect(model.activeSource == candidate)
        #expect(model.snapshot?.source == candidate)
        #expect(model.snapshot?.quote(for: code("JPY"))?.rate == Decimal(string: "151"))
        #expect(model.lastAttempt?.source == candidate)
        #expect(model.lastAttempt?.attemptedAt == clock.value)
        #expect(model.lastAttempt?.outcome == .success)
        #expect(model.nextAutomaticRefreshAt
                == clock.value.addingTimeInterval(CurrencyModel.automaticRefreshInterval))
        #expect(!model.isEligible)
        #expect(await provider.sources == [candidate])

        let persisted = store.loadPersistentState()
        #expect(persisted.sourcePreferences == model.sourcePreferences)
        #expect(persisted.snapshot == model.snapshot)
        #expect(persisted.attempt == model.lastAttempt)
    }

    @Test func failedSourceValidationPreservesPriorStateAndDoesNotFetchAnotherSource() async throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        let oldSource = customSource(.frankfurter, suffix: "stable/rates")
        var oldPreferences = ExchangeRateSourcePreferences.default
        oldPreferences.activate(oldSource)
        let oldSnapshot = ExchangeRateSnapshot(
            source: oldSource,
            fetchedAt: Date(timeIntervalSince1970: 1_000),
            quotes: [quote("CNY", rate: "7.0")]
        )
        let oldAttempt = ExchangeRateAttempt(
            attemptedAt: Date(timeIntervalSince1970: 2_000),
            outcome: .success,
            errorDescription: nil,
            source: oldSource
        )
        let oldState = ExchangeRatePersistentState(
            schemaVersion: ExchangeRatePersistentState.currentSchemaVersion,
            sourcePreferences: oldPreferences,
            snapshot: oldSnapshot,
            attempt: oldAttempt
        )
        store.savePersistentState(oldState)
        let candidate = defaultSource(.ecb)
        let provider = RateProviderStub(responses: [.failure])
        let model = CurrencyModel(
            provider: provider,
            store: store,
            schedulesAutomaticRefresh: false
        )

        let succeeded = await model.validateAndActivateSource(
            providerID: candidate.providerID,
            endpointText: candidate.endpoint.absoluteString
        )
        try await Task.sleep(for: .milliseconds(50))

        #expect(!succeeded)
        #expect(model.sourceValidationError != nil)
        #expect(model.activeSource == oldSource)
        #expect(model.sourcePreferences == oldPreferences)
        #expect(model.snapshot == oldSnapshot)
        #expect(model.lastAttempt == oldAttempt)
        #expect(store.loadPersistentState() == oldState)
        #expect(await provider.sources == [candidate])
    }

    @Test func failedSourceValidationDoesNotImmediatelyRefreshAnEligibleOldSource() async throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        let clock = CurrencyTestClock(Date(timeIntervalSince1970: 200_000))
        let oldAttempt = ExchangeRateAttempt(
            attemptedAt: Date(timeIntervalSince1970: 1_000),
            outcome: .success,
            errorDescription: nil
        )
        store.savePersistentState(ExchangeRatePersistentState(
            schemaVersion: ExchangeRatePersistentState.currentSchemaVersion,
            sourcePreferences: .default,
            snapshot: ExchangeRateSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_000),
                quotes: [quote("CNY", rate: "7.0")]
            ),
            attempt: oldAttempt
        ))
        let provider = RateProviderStub(
            responses: [.failure],
            delay: .milliseconds(100)
        )
        let model = CurrencyModel(
            provider: provider,
            store: store,
            now: { clock.value },
            schedulesAutomaticRefresh: true
        )
        let candidate = defaultSource(.exchangeRateAPI)

        let validation = Task {
            await model.validateAndActivateSource(
                providerID: candidate.providerID,
                endpointText: candidate.endpoint.absoluteString
            )
        }
        try await waitForRequests(1, from: provider)
        let initialRefresh = model.start()
        await initialRefresh?.value

        let succeeded = await validation.value
        #expect(!succeeded)
        try await Task.sleep(for: .milliseconds(150))
        #expect(await provider.sources == [candidate])
        #expect(model.activeSource == .default)
        #expect(model.lastAttempt == oldAttempt)
    }

    @Test func validatingTheAlreadyActiveSourceDoesNotRequestAgain() async throws {
        let defaults = try makeDefaults()
        let provider = RateProviderStub(responses: [])
        let model = CurrencyModel(
            provider: provider,
            store: ExchangeRateStore(defaults: defaults),
            schedulesAutomaticRefresh: false
        )

        let succeeded = await model.validateAndActivateSource(
            providerID: .frankfurter,
            endpointText: "HTTPS://API.FRANKFURTER.DEV/v2/rates?base=USD"
        )

        #expect(succeeded)
        #expect(model.activeSource == .default)
        #expect(model.sourceValidationError == nil)
        #expect(await provider.count == 0)
    }

    @Test func concurrentSourceValidationsCoalesceBehindTheInFlightCandidate() async throws {
        let defaults = try makeDefaults()
        let firstCandidate = defaultSource(.exchangeRateAPI)
        let secondCandidate = defaultSource(.ecb)
        let provider = RateProviderStub(
            responses: [.success([quote("JPY", rate: "151")])],
            delay: .milliseconds(100)
        )
        let model = CurrencyModel(
            provider: provider,
            store: ExchangeRateStore(defaults: defaults),
            schedulesAutomaticRefresh: false
        )

        let first = Task {
            await model.validateAndActivateSource(
                providerID: firstCandidate.providerID,
                endpointText: firstCandidate.endpoint.absoluteString
            )
        }
        try await waitForRequests(1, from: provider)
        let second = await model.validateAndActivateSource(
            providerID: secondCandidate.providerID,
            endpointText: secondCandidate.endpoint.absoluteString
        )

        #expect(!second)
        #expect(await first.value)
        #expect(await provider.sources == [firstCandidate])
        #expect(model.activeSource == firstCandidate)
        #expect(model.snapshot?.source == firstCandidate)
    }

    @Test func switchingToECBWithoutTheSelectedQuoteFallsBackHonestlyToUSD() async throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        store.saveSelection(.fixed(code("CNY")))
        store.saveSnapshot(ExchangeRateSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 100),
            quotes: [quote("CNY", rate: "7.0")]
        ))
        let candidate = defaultSource(.ecb)
        let provider = RateProviderStub(responses: [
            .success([quote("JPY", rate: "151")]),
        ])
        let model = CurrencyModel(
            provider: provider,
            store: store,
            locale: { Locale(identifier: "zh_CN") },
            schedulesAutomaticRefresh: false
        )

        #expect(model.displayContext.currencyCode == code("CNY"))
        #expect(!model.displayContext.isFallback)
        #expect(await model.validateAndActivateSource(
            providerID: candidate.providerID,
            endpointText: candidate.endpoint.absoluteString
        ))

        #expect(model.selection == .fixed(code("CNY")))
        #expect(model.snapshot?.source == candidate)
        #expect(model.displayContext.requestedCode == code("CNY"))
        #expect(model.displayContext.currencyCode == .usd)
        #expect(model.displayContext.rate == 1)
        #expect(model.displayContext.isFallback)
    }

    @Test func fixedUSDWorksWithoutAnExchangeRateCache() throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        store.saveSelection(.fixed(.usd))

        let model = CurrencyModel(
            provider: RateProviderStub(responses: []),
            store: store,
            locale: { Locale(identifier: "zh_CN") },
            schedulesAutomaticRefresh: false
        )

        #expect(model.selection == .fixed(.usd))
        #expect(model.availableCurrencies == [.usd])
        #expect(model.displayContext.currencyCode == .usd)
        #expect(!model.displayContext.isFallback)
    }

    @Test func automaticRefreshIsLimitedToOneAttemptPerRollingDay() async throws {
        let defaults = try makeDefaults()
        let clock = CurrencyTestClock(Date(timeIntervalSince1970: 10_000))
        let provider = RateProviderStub(responses: [
            .success([quote("CNY", rate: "7.1")]),
            .success([quote("CNY", rate: "7.2")]),
        ])
        let model = CurrencyModel(
            provider: provider,
            store: ExchangeRateStore(defaults: defaults),
            now: { clock.value },
            locale: { Locale(identifier: "zh_CN") },
            schedulesAutomaticRefresh: false
        )

        await model.refreshIfEligible()
        await model.refreshIfEligible()
        #expect(await provider.count == 1)
        #expect(!model.isEligible)

        clock.value.addTimeInterval(CurrencyModel.automaticRefreshInterval)
        await model.refreshIfEligible()
        #expect(await provider.count == 2)
    }

    @Test func failedAttemptKeepsLastGoodAndAllowsExplicitRetry() async throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        let clock = CurrencyTestClock(Date(timeIntervalSince1970: 200_000))
        let oldSnapshot = ExchangeRateSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 100),
            quotes: [quote("CNY", rate: "7.0")]
        )
        store.saveSnapshot(oldSnapshot)
        let provider = RateProviderStub(responses: [
            .failure,
            .success([quote("CNY", rate: "7.2")]),
        ])
        let model = CurrencyModel(
            provider: provider,
            store: store,
            now: { clock.value },
            locale: { Locale(identifier: "zh_CN") },
            schedulesAutomaticRefresh: false
        )

        await model.refreshIfEligible()
        #expect(model.snapshot == oldSnapshot)
        #expect(model.canRetry)
        #expect(model.lastError != nil)
        #expect(!model.isEligible)
        let failedAttemptNextEligibility = model.nextAutomaticRefreshAt

        clock.value.addTimeInterval(123)
        await model.retryNow()
        #expect(await provider.count == 2)
        #expect(model.snapshot?.quote(for: code("CNY"))?.rate == Decimal(string: "7.2"))
        #expect(model.lastError == nil)
        #expect(!model.canRetry)
        #expect(model.nextAutomaticRefreshAt
                == clock.value.addingTimeInterval(CurrencyModel.automaticRefreshInterval))
        #expect(model.nextAutomaticRefreshAt != failedAttemptNextEligibility)
    }

    @Test func failedAttemptDoesNotArmABackgroundRetryTimer() async throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        let clock = CurrencyTestClock(Date(timeIntervalSince1970: 400_000))
        let nextEligibilityDelay: TimeInterval = 0.1
        store.saveAttempt(ExchangeRateAttempt(
            attemptedAt: clock.value.addingTimeInterval(
                -CurrencyModel.automaticRefreshInterval + nextEligibilityDelay
            ),
            outcome: .failure,
            errorDescription: "Offline"
        ))
        let provider = RateProviderStub(responses: [
            .success([quote("CNY", rate: "7.1")]),
        ])
        let model = CurrencyModel(
            provider: provider,
            store: store,
            now: { clock.value },
            locale: { Locale(identifier: "zh_CN") }
        )

        model.start()
        // Let start's eligibility check observe the still-ineligible clock and
        // either arm (the regression) or decline (the intended behavior) its
        // timer before making the persisted attempt eligible.
        try await Task.sleep(for: .milliseconds(50))
        clock.value.addTimeInterval(1)
        try await Task.sleep(for: .milliseconds(250))

        #expect(await provider.count == 0)
        #expect(model.lastAttempt?.outcome == .failure)
        #expect(model.canRetry)
    }

    @Test func overlappingRefreshTriggersCoalesce() async throws {
        let defaults = try makeDefaults()
        let provider = RateProviderStub(
            responses: [.success([quote("CNY", rate: "7.1")])],
            delay: .milliseconds(100)
        )
        let model = CurrencyModel(
            provider: provider,
            store: ExchangeRateStore(defaults: defaults),
            schedulesAutomaticRefresh: false
        )

        let first = Task { await model.refreshIfEligible() }
        await Task.yield()
        let second = Task { await model.refreshIfEligible() }
        await first.value
        await second.value

        #expect(await provider.count == 1)
    }

    @Test func activationAndWakeTriggersCoalesceBehindOneInFlightRequest() async throws {
        let defaults = try makeDefaults()
        let provider = RateProviderStub(
            responses: [.success([quote("CNY", rate: "7.1")])],
            delay: .milliseconds(100)
        )
        let model = CurrencyModel(
            provider: provider,
            store: ExchangeRateStore(defaults: defaults),
            schedulesAutomaticRefresh: false
        )

        model.start()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(250))

        #expect(await provider.count == 1)
        #expect(model.lastAttempt?.outcome == .success)
    }

    @Test func scheduledEligibilityDoesNotCancelItsOwnFetch() async throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        let startedAt = Date()
        store.saveAttempt(ExchangeRateAttempt(
            attemptedAt: startedAt.addingTimeInterval(
                -CurrencyModel.automaticRefreshInterval + 0.4
            ),
            outcome: .success,
            errorDescription: nil
        ))
        let provider = RateProviderStub(
            responses: [.success([quote("CNY", rate: "7.1")])],
            delay: .milliseconds(50)
        )
        let model = CurrencyModel(
            provider: provider,
            store: store,
            now: Date.init,
            locale: { Locale(identifier: "zh_CN") }
        )

        model.start()
        let waitClock = ContinuousClock()
        let deadline = waitClock.now.advanced(by: .seconds(3))
        while model.snapshot == nil, waitClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(await provider.count == 1)
        #expect(model.snapshot?.quote(for: code("CNY"))?.rate == Decimal(string: "7.1"))
        #expect(model.lastAttempt?.outcome == .success)
    }

    @Test func unavailableSystemQuoteFallsBackHonestlyToUSD() throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        store.saveSelection(.system)
        store.saveSnapshot(ExchangeRateSnapshot(
            fetchedAt: Date(),
            quotes: [quote("JPY", rate: "150")]
        ))
        let model = CurrencyModel(
            provider: RateProviderStub(responses: []),
            store: store,
            locale: { Locale(identifier: "zh_CN") },
            schedulesAutomaticRefresh: false
        )

        #expect(model.displayContext.requestedCode == code("CNY"))
        #expect(model.displayContext.currencyCode == .usd)
        #expect(model.displayContext.isFallback)
        #expect(model.displayContext.rate == 1)
    }

    @Test func systemSelectionReResolvesLocaleWithoutFetching() async throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        store.saveSelection(.system)
        let now = Date(timeIntervalSince1970: 50_000)
        store.saveAttempt(ExchangeRateAttempt(
            attemptedAt: now,
            outcome: .success,
            errorDescription: nil
        ))
        let locale = CurrencyLocaleBox(Locale(identifier: "zh_CN"))
        let provider = RateProviderStub(responses: [])
        let model = CurrencyModel(
            provider: provider,
            store: store,
            now: { now },
            locale: { locale.value },
            schedulesAutomaticRefresh: false
        )
        model.start()
        await Task.yield()
        #expect(model.requestedCurrencyCode == code("CNY"))

        locale.value = Locale(identifier: "ja_JP")
        NotificationCenter.default.post(
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
        await Task.yield()

        #expect(model.requestedCurrencyCode == code("JPY"))
        #expect(await provider.count == 0)
    }

    @Test func conversionRoundsOnlyOnceAtTheTargetMinorUnit() {
        let cny = context(code: "CNY", rate: "7")
        let jpy = context(code: "JPY", rate: "150")
        let kwd = context(code: "KWD", rate: "0.3")

        let cnyAmount = cny.amount(forUSD: Decimal(string: "0.004")!)
        #expect(cnyAmount.exactValue == Decimal(string: "0.028"))
        #expect(cnyAmount.roundedValue == Decimal(string: "0.03"))
        #expect(jpy.amount(forUSD: Decimal(string: "0.0801")!).roundedValue == 13)
        #expect(kwd.amount(forUSD: Decimal(string: "0.0001")!).roundedValue == Decimal(string: "0.001"))
        #expect(CurrencyAmountFormatting.minorUnits(for: code("JPY")) == 0)
        #expect(CurrencyAmountFormatting.minorUnits(for: code("KWD")) == 3)
    }

    @Test func rateDateRenderingKeepsTheUTCQuoteDayInNegativeTimeZones() throws {
        let parser = ISO8601DateFormatter()
        let quoteDate = try #require(parser.date(from: "2026-08-01T00:00:00Z"))
        let locale = Locale(identifier: "en_US")

        let localFormatter = DateFormatter()
        localFormatter.locale = locale
        localFormatter.calendar = Calendar(identifier: .gregorian)
        localFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        localFormatter.dateStyle = .medium
        localFormatter.timeStyle = .none

        let rendered = CurrencyAmountFormatting.rateDateText(quoteDate, locale: locale)
        #expect(localFormatter.string(from: quoteDate).contains("Jul 31"))
        #expect(rendered.contains("Aug 1"))
        #expect(!rendered.contains("Jul 31"))
    }

    private func context(code value: String, rate: String) -> CurrencyDisplayContext {
        let currency = code(value)
        return CurrencyDisplayContext(
            requestedCode: currency,
            currencyCode: currency,
            rate: Decimal(string: rate)!,
            rateDate: Date(timeIntervalSince1970: 100),
            fetchedAt: Date(timeIntervalSince1970: 200),
            isStale: false,
            isFallback: false,
            localeIdentifier: "en_US"
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "CurrencyModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class CurrencyTestClock {
    var value: Date
    init(_ value: Date) { self.value = value }
}

private final class CurrencyLocaleBox {
    var value: Locale
    init(_ value: Locale) { self.value = value }
}

private enum RateProviderResponse: Sendable {
    case success([ExchangeRateQuote])
    case failure
}

private actor RateProviderStub: ExchangeRateProviding {
    private var responses: [RateProviderResponse]
    private let delay: Duration?
    private(set) var count = 0
    private(set) var sources: [ExchangeRateSource] = []

    init(responses: [RateProviderResponse], delay: Duration? = nil) {
        self.responses = responses
        self.delay = delay
    }

    func fetchRates(from source: ExchangeRateSource) async throws -> [ExchangeRateQuote] {
        count += 1
        sources.append(source)
        if let delay { try await Task.sleep(for: delay) }
        guard !responses.isEmpty else { throw TestRateError.noResponse }
        switch responses.removeFirst() {
        case let .success(quotes): return quotes
        case .failure: throw TestRateError.failed
        }
    }
}

private enum TestRateError: Error { case noResponse, failed }

private struct LegacySnapshotFixture: Encodable {
    let schemaVersion: Int
    let baseCode: CurrencyCode
    let fetchedAt: Date
    let quotes: [ExchangeRateQuote]
}

private struct LegacyAttemptFixture: Encodable {
    let attemptedAt: Date
    let outcome: ExchangeRateAttemptOutcome
    let errorDescription: String?
}

private func defaultSource(_ providerID: ExchangeRateProviderID) -> ExchangeRateSource {
    ExchangeRateSource(
        providerID: providerID,
        endpoint: providerID.descriptor.defaultEndpoint
    )
}

private func customSource(
    _ providerID: ExchangeRateProviderID,
    suffix: String
) -> ExchangeRateSource {
    try! ExchangeRateSource.validated(
        providerID: providerID,
        endpointText: "https://rates.example.test/\(suffix)"
    )
}

private func waitForRequests(
    _ expectedCount: Int,
    from provider: RateProviderStub
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while await provider.count < expectedCount, clock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await provider.count == expectedCount)
}

private func code(_ value: String) -> CurrencyCode {
    CurrencyCode(value)!
}

private func quote(_ value: String, rate: String) -> ExchangeRateQuote {
    ExchangeRateQuote(
        quoteCode: code(value),
        rate: Decimal(string: rate)!,
        rateDate: Date(timeIntervalSince1970: 100)
    )
}
