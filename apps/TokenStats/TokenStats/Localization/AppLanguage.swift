//
//  AppLanguage.swift
//  TokenStats
//
//  The user-selectable language override. Language is deliberately separate
//  from region and formatting preferences: choosing English or Simplified
//  Chinese changes TokenStats' copy while retaining the Mac's regional rules.
//

import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Let the process use the language selected for TokenStats by macOS.
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: Self { self }

    /// Language names are intentionally written in their own language so they
    /// remain recognizable even when the current UI language is unfamiliar.
    var pickerTitle: LocalizedStringResource {
        switch self {
        case .system:
            LocalizedStringResource.settingsGeneralLanguageOptionSystem
        case .english:
            LocalizedStringResource.settingsGeneralLanguageOptionEnglish
        case .simplifiedChinese:
            LocalizedStringResource.settingsGeneralLanguageOptionSimplifiedChinese
        }
    }

    /// Builds the UI locale from the system's regional locale. Only language
    /// and script are replaced, preserving region, calendar, numbering system,
    /// hour cycle, measurement system, currency, and the rest of the user's
    /// format choices. Follow System uses the localization macOS selected for
    /// this app, which can differ from the language in `Locale.current`.
    func locale(
        basedOn systemLocale: Locale,
        appPreferredLocalization: String? = nil
    ) -> Locale {
        var components = Locale.Components(locale: systemLocale)
        switch self {
        case .system:
            guard let appPreferredLocalization,
                  appPreferredLocalization.caseInsensitiveCompare("Base") != .orderedSame
            else { return systemLocale }

            let preferredLanguage = Locale.Components(
                identifier: appPreferredLocalization
            ).languageComponents
            guard let languageCode = preferredLanguage.languageCode else { return systemLocale }
            if components.languageComponents.languageCode == languageCode,
               components.languageComponents.script == preferredLanguage.script {
                return systemLocale
            }
            components.languageComponents.languageCode = languageCode
            components.languageComponents.script = preferredLanguage.script
        case .english:
            components.languageComponents.languageCode = .english
            components.languageComponents.script = nil
        case .simplifiedChinese:
            components.languageComponents.languageCode = .chinese
            components.languageComponents.script = .hanSimplified
        }
        return Locale(components: components)
    }
}
