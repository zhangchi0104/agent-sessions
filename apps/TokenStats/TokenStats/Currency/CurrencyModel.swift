//
//  CurrencyModel.swift
//  TokenStats
//
//  Main-actor coordinator for display preference, last-known-good rates, and
//  the single rolling-24-hour automatic request.
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class CurrencyModel {
    static let automaticRefreshInterval: TimeInterval = 24 * 60 * 60

    var selection: DisplayCurrencySelection {
        didSet {
            guard selection != oldValue else { return }
            store.saveSelection(selection)
        }
    }

    private(set) var sourcePreferences: ExchangeRateSourcePreferences
    private(set) var snapshot: ExchangeRateSnapshot?
    private(set) var lastAttempt: ExchangeRateAttempt?
    private(set) var isRefreshing = false
    private(set) var isValidatingSource = false
    private(set) var lastError: String?
    private(set) var sourceValidationError: String?
    private(set) var systemCurrencyCode: CurrencyCode
    private(set) var localeIdentifier: String

    @ObservationIgnored private let provider: any ExchangeRateProviding
    @ObservationIgnored private let store: ExchangeRateStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let locale: () -> Locale
    @ObservationIgnored private let schedulesAutomaticRefresh: Bool
    @ObservationIgnored private var automaticRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var localeObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false

    init(
        provider: any ExchangeRateProviding = ExchangeRateProviderRouter(),
        store: ExchangeRateStore = ExchangeRateStore(),
        now: @escaping () -> Date = Date.init,
        locale: @escaping () -> Locale = { .autoupdatingCurrent },
        schedulesAutomaticRefresh: Bool = true
    ) {
        self.provider = provider
        self.store = store
        self.now = now
        self.locale = locale
        self.schedulesAutomaticRefresh = schedulesAutomaticRefresh
        selection = store.loadSelection()
        let persistentState = store.loadPersistentState()
        sourcePreferences = persistentState.sourcePreferences
        snapshot = persistentState.snapshot
        lastAttempt = persistentState.attempt
        let initialLocale = locale()
        systemCurrencyCode = Self.resolveSystemCurrency(from: initialLocale)
        localeIdentifier = initialLocale.identifier
        if let lastAttempt {
            switch lastAttempt.outcome {
            case .failure:
                lastError = lastAttempt.errorDescription ?? "The last exchange-rate request failed."
            case .pending:
                lastError = "The previous exchange-rate request did not complete."
            case .success:
                lastError = nil
            }
        }
    }

    deinit {
        automaticRefreshTask?.cancel()
        if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    var requestedCurrencyCode: CurrencyCode {
        switch selection {
        case .system: systemCurrencyCode
        case let .fixed(code): code
        }
    }

    var activeSource: ExchangeRateSource {
        sourcePreferences.activeSource
    }

    var availableSourceDescriptors: [ExchangeRateProviderDescriptor] {
        ExchangeRateProviderID.allCases.map(\.descriptor)
    }

    func configuredSource(for providerID: ExchangeRateProviderID) -> ExchangeRateSource {
        sourcePreferences.source(for: providerID)
    }

    var availableCurrencies: [CurrencyCode] {
        var codes = Set(snapshot?.quotes.map(\.quoteCode) ?? [])
        codes.insert(.usd)
        return codes.sorted()
    }

    var isEligible: Bool {
        guard let lastAttempt else { return true }
        return now().timeIntervalSince(lastAttempt.attemptedAt) >= Self.automaticRefreshInterval
    }

    var nextAutomaticRefreshAt: Date? {
        lastAttempt?.attemptedAt.addingTimeInterval(Self.automaticRefreshInterval)
    }

    var canRetry: Bool {
        guard !isRefreshing, !isValidatingSource, let lastAttempt else { return false }
        return lastAttempt.outcome == .failure || lastAttempt.outcome == .pending
    }

    var isSnapshotStale: Bool {
        guard let snapshot else { return false }
        return now().timeIntervalSince(snapshot.fetchedAt) >= Self.automaticRefreshInterval
    }

    var displayContext: CurrencyDisplayContext {
        let requested = requestedCurrencyCode
        if requested == .usd {
            return CurrencyDisplayContext(
                requestedCode: requested,
                currencyCode: .usd,
                rate: 1,
                rateDate: nil,
                fetchedAt: snapshot?.fetchedAt,
                isStale: false,
                isFallback: false,
                localeIdentifier: localeIdentifier
            )
        }

        if let snapshot, let quote = snapshot.quote(for: requested) {
            return CurrencyDisplayContext(
                requestedCode: requested,
                currencyCode: requested,
                rate: quote.rate,
                rateDate: quote.rateDate,
                fetchedAt: snapshot.fetchedAt,
                isStale: isSnapshotStale,
                isFallback: false,
                localeIdentifier: localeIdentifier
            )
        }

        return CurrencyDisplayContext(
            requestedCode: requested,
            currencyCode: .usd,
            rate: 1,
            rateDate: nil,
            fetchedAt: snapshot?.fetchedAt,
            isStale: false,
            isFallback: true,
            localeIdentifier: localeIdentifier
        )
    }

    /// Restore lifecycle observation and perform the single eligible automatic
    /// check. Repeated calls are harmless.
    @discardableResult
    func start() -> Task<Void, Never>? {
        guard !started else { return nil }
        started = true
        observeSystemChanges()
        let initialRefresh = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.refreshIfEligible()
        }
        return initialRefresh
    }

    func refreshIfEligible() async {
        guard !isRefreshing, !isValidatingSource else { return }
        guard isEligible else {
            scheduleNextAutomaticRefresh()
            return
        }
        await refresh(force: false)
    }

    /// The sole rate-limit override. The Settings UI exposes it only after a
    /// failed or interrupted attempt, and every click is one explicit request.
    func retryNow() async {
        guard canRetry else { return }
        await refresh(force: true)
    }

    /// Validate one known adapter against a candidate HTTPS endpoint, then
    /// atomically make the candidate and its newly fetched table active. A
    /// failed validation leaves the current source, cache, and daily gate intact.
    @discardableResult
    func validateAndActivateSource(
        providerID: ExchangeRateProviderID,
        endpointText: String
    ) async -> Bool {
        let candidate: ExchangeRateSource
        do {
            candidate = try ExchangeRateSource.validated(
                providerID: providerID,
                endpointText: endpointText
            )
        } catch {
            sourceValidationError = Self.errorDetail(error)
            return false
        }

        guard candidate != activeSource else {
            sourceValidationError = nil
            return true
        }
        // A second Apply arriving while validation is in flight is a no-op. It
        // must not overwrite the first operation's eventual success/error.
        guard !isValidatingSource else { return false }
        guard !isRefreshing else {
            sourceValidationError = "Wait for the current exchange-rate request to finish."
            return false
        }

        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        isValidatingSource = true
        sourceValidationError = nil

        let attemptedAt = now()
        var didActivate = false
        do {
            let quotes = try await provider.fetchRates(from: candidate)
            try Task.checkCancellation()
            let fetched = ExchangeRateSnapshot(
                source: candidate,
                fetchedAt: now(),
                quotes: quotes
            )
            guard fetched.isValidEnvelope else {
                throw ExchangeRateProviderError.emptyTable(candidate.providerID)
            }

            var preferences = sourcePreferences
            preferences.activate(candidate)
            let success = ExchangeRateAttempt(
                attemptedAt: attemptedAt,
                outcome: .success,
                errorDescription: nil,
                source: candidate
            )
            let newState = ExchangeRatePersistentState(
                schemaVersion: ExchangeRatePersistentState.currentSchemaVersion,
                sourcePreferences: preferences,
                snapshot: fetched,
                attempt: success
            )
            guard newState.isValidEnvelope else {
                throw ExchangeRateProviderError.emptyTable(candidate.providerID)
            }

            sourcePreferences = preferences
            snapshot = fetched
            lastAttempt = success
            lastError = nil
            sourceValidationError = nil
            store.savePersistentState(newState)
            didActivate = true
        } catch {
            sourceValidationError = Self.errorDetail(error)
        }

        isValidatingSource = false
        if didActivate {
            scheduleNextAutomaticRefresh()
        } else {
            restoreFutureAutomaticRefreshAfterFailedValidation()
        }
        return didActivate
    }

    func clearSourceValidationError() {
        sourceValidationError = nil
    }

    private func refresh(force: Bool) async {
        guard !isRefreshing, !isValidatingSource else { return }
        guard force || isEligible else {
            scheduleNextAutomaticRefresh()
            return
        }

        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil

        let source = activeSource
        let attemptedAt = now()
        let pending = ExchangeRateAttempt(
            attemptedAt: attemptedAt,
            outcome: .pending,
            errorDescription: nil,
            source: source
        )
        lastAttempt = pending
        persistState()
        lastError = nil
        isRefreshing = true

        do {
            let quotes = try await provider.fetchRates(from: source)
            let fetched = ExchangeRateSnapshot(
                source: source,
                fetchedAt: now(),
                quotes: quotes
            )
            guard fetched.isValidEnvelope else {
                throw ExchangeRateProviderError.emptyTable(source.providerID)
            }
            snapshot = fetched
            let success = ExchangeRateAttempt(
                attemptedAt: attemptedAt,
                outcome: .success,
                errorDescription: nil,
                source: source
            )
            lastAttempt = success
            persistState()
        } catch {
            let detail = Self.errorDetail(error)
            lastError = detail
            let failure = ExchangeRateAttempt(
                attemptedAt: attemptedAt,
                outcome: .failure,
                errorDescription: detail,
                source: source
            )
            lastAttempt = failure
            persistState()
        }

        isRefreshing = false
        scheduleNextAutomaticRefresh()
    }

    private func persistState() {
        store.savePersistentState(ExchangeRatePersistentState(
            schemaVersion: ExchangeRatePersistentState.currentSchemaVersion,
            sourcePreferences: sourcePreferences,
            snapshot: snapshot,
            attempt: lastAttempt
        ))
    }

    private func scheduleNextAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        guard started, schedulesAutomaticRefresh else { return }
        // A failed or interrupted request must not create a background retry
        // loop. Lifecycle events can perform the next eligible automatic check,
        // and Settings exposes the only immediate rate-limit override.
        guard lastAttempt?.outcome == .success else { return }

        let delay: TimeInterval
        if let nextAutomaticRefreshAt {
            delay = max(0, nextAutomaticRefreshAt.timeIntervalSince(now()))
        } else {
            delay = 0
        }

        automaticRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            // Clear the timer handle before entering the refresh path. Otherwise
            // `refresh` would cancel the currently executing timer task and that
            // cancellation would propagate into URLSession.data(for:).
            self?.automaticRefreshTask = nil
            await self?.refreshIfEligible()
        }
    }

    /// Source validation is one explicit request. If it fails after an already
    /// eligible automatic check was coalesced behind it, do not immediately
    /// issue a second request to the still-active source. A future lifecycle
    /// event may perform that eligible check. Timers that were not yet due are
    /// restored so a failed validation does not postpone the normal schedule.
    private func restoreFutureAutomaticRefreshAfterFailedValidation() {
        guard let nextAutomaticRefreshAt, nextAutomaticRefreshAt > now() else { return }
        scheduleNextAutomaticRefresh()
    }

    private func observeSystemChanges() {
        guard localeObserver == nil else { return }
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshSystemCurrency()
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.requestEligibleRefresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.requestEligibleRefresh()
            }
        }
    }

    private func requestEligibleRefresh() {
        Task { await refreshIfEligible() }
    }

    private func refreshSystemCurrency() {
        let currentLocale = locale()
        systemCurrencyCode = Self.resolveSystemCurrency(from: currentLocale)
        localeIdentifier = currentLocale.identifier
    }

    private static func resolveSystemCurrency(from locale: Locale) -> CurrencyCode {
        guard let identifier = locale.currency?.identifier,
              let code = CurrencyCode(identifier)
        else { return .usd }
        return code
    }

    private static func errorDetail(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }
}
