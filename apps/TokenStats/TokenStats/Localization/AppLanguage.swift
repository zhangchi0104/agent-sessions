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

    /// Builds the UI locale from the system locale. Only language and script
    /// are replaced, preserving region, calendar, numbering system, hour cycle,
    /// measurement system, currency, and the rest of the user's format choices.
    func locale(basedOn systemLocale: Locale) -> Locale {
        guard self != .system else { return systemLocale }

        var components = Locale.Components(locale: systemLocale)
        switch self {
        case .system:
            break
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
