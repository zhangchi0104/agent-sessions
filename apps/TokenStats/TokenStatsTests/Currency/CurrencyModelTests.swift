//
//  CurrencyModelTests.swift
//  TokenStatsTests
//

import AppKit
import Foundation
import Testing
@testable import TokenStats

@MainActor
struct CurrencyModelTests {
    @Test func missingAndDamagedPreferencesFollowTheSystemRegion() throws {
        let defaults = try makeDefaults()
        let store = ExchangeRateStore(defaults: defaults)
        #expect(store.loadSelection() == .system)

        defaults.set(Data("not-json".utf8), forKey: "currency.displaySelection.v1")
        let model = CurrencyModel(
            provider: RateProviderStub(responses: []),
            store: store,
            locale: { Locale(identifier: "zh_CN") },
            schedulesAutomaticRefresh: false
        )

        #expect(model.selection == .system)
        #expect(model.requestedCurrencyCode == code("CNY"))
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

    init(responses: [RateProviderResponse], delay: Duration? = nil) {
        self.responses = responses
        self.delay = delay
    }

    func fetchRates() async throws -> [ExchangeRateQuote] {
        count += 1
        if let delay { try await Task.sleep(for: delay) }
        guard !responses.isEmpty else { throw TestRateError.noResponse }
        switch responses.removeFirst() {
        case let .success(quotes): return quotes
        case .failure: throw TestRateError.failed
        }
    }
}

private enum TestRateError: Error { case noResponse, failed }

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
