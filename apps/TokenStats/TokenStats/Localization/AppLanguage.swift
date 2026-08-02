//
//  AppLanguage.swift
//  TokenStats
//
//  The user-selectable language override. Language is deliberately separate
//  from region and formatting preferences: choosing a language changes
//  TokenStats' copy while retaining the Mac's regional rules.
//

import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Let the process use the language selected for TokenStats by macOS.
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case german = "de"
    case french = "fr"
    case japanese = "ja"
    case russian = "ru"

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
        case .german:
            LocalizedStringResource.settingsGeneralLanguageOptionGerman
        case .french:
            LocalizedStringResource.settingsGeneralLanguageOptionFrench
        case .japanese:
            LocalizedStringResource.settingsGeneralLanguageOptionJapanese
        case .russian:
            LocalizedStringResource.settingsGeneralLanguageOptionRussian
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
        case .english, .simplifiedChinese, .german, .french, .japanese, .russian:
            let explicitLanguage = Locale.Components(identifier: rawValue).languageComponents
            guard let languageCode = explicitLanguage.languageCode else { return systemLocale }
            components.languageComponents.languageCode = languageCode
            // Clear a script inherited from the system Locale when the target
            // language does not declare one. This prevents invalid composites
            // such as de-Hans when switching away from Simplified Chinese.
            components.languageComponents.script = explicitLanguage.script
        }
        return Locale(components: components)
    }
}
