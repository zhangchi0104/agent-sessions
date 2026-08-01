//
//  LocalizationSettings.swift
//  TokenStats
//
//  Persists a user's requested app language while freezing the effective
//  language and Locale for the lifetime of the current process. This prevents
//  a half-localized UI when the preference changes; a relaunch applies it.
//

import Foundation
import Observation

@MainActor
@Observable
final class LocalizationSettings {
    /// The language to apply on the next launch. Updating it persists at once.
    var preferredLanguage: AppLanguage {
        didSet {
            defaults.set(preferredLanguage.rawValue, forKey: Self.persistenceKey)
        }
    }

    /// The preference read at process startup. It never changes in-process.
    let effectiveLanguage: AppLanguage

    /// The process-wide UI Locale derived at startup. It keeps the system's
    /// formatting components even when TokenStats' language is overridden.
    let effectiveLocale: Locale

    @ObservationIgnored private let defaults: UserDefaults

    static let persistenceKey = "localization.preferredLanguage"

    init(
        defaults: UserDefaults = .standard,
        systemLocale: Locale = .current,
        // Bundle preference honors macOS's per-app language without borrowing
        // its region, which continues to come from the system Locale above.
        appPreferredLocalization: String? = Bundle.main.preferredLocalizations.first
    ) {
        self.defaults = defaults

        let storedObject = defaults.object(forKey: Self.persistenceKey)
        let storedValue = storedObject as? String
        let startupLanguage = storedValue.flatMap(AppLanguage.init(rawValue:)) ?? .system

        // Repair an unknown value so future launches do not repeatedly depend
        // on fallback behavior after a downgrade or corrupted preference.
        if storedObject != nil && storedValue.flatMap(AppLanguage.init(rawValue:)) == nil {
            defaults.removeObject(forKey: Self.persistenceKey)
        }

        preferredLanguage = startupLanguage
        effectiveLanguage = startupLanguage
        effectiveLocale = startupLanguage.locale(
            basedOn: systemLocale,
            appPreferredLocalization: appPreferredLocalization
        )
    }

    /// True only while the saved preference differs from what this process is
    /// displaying. Selecting the current language again cancels the pending
    /// change without any additional bookkeeping.
    var needsRestart: Bool {
        preferredLanguage != effectiveLanguage
    }

    var localizer: AppLocalizer {
        AppLocalizer(locale: effectiveLocale)
    }
}
