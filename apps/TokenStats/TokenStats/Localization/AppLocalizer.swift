//
//  AppLocalizer.swift
//  TokenStats
//
//  A single locale-aware bridge for copy produced outside SwiftUI, including
//  AppKit titles, presentation models, errors, accessibility, and HTML.
//

import Foundation

nonisolated struct AppLocalizer: Sendable {
    let locale: Locale

    init(locale: Locale) {
        self.locale = locale
    }

    /// Returns a resource pinned to this process' effective UI locale. SwiftUI
    /// roots also receive the locale through the environment, but this is handy
    /// for resources passed across an AppKit or presentation-model boundary.
    func resource(_ resource: LocalizedStringResource) -> LocalizedStringResource {
        var localizedResource = resource
        localizedResource.locale = locale
        return localizedResource
    }

    /// Resolves localized copy for APIs that require a concrete String.
    func localized(_ resource: LocalizedStringResource) -> String {
        String(localized: self.resource(resource))
    }

    /// A standards-based language tag for generated markup such as OAuth
    /// callback HTML. Formatting-only locale extensions are intentionally not
    /// included in the document language.
    var htmlLanguageTag: String {
        let components = Locale.Components(locale: locale).languageComponents
        guard let languageCode = components.languageCode?.identifier else { return "und" }
        guard let script = components.script?.identifier else { return languageCode }
        return "\(languageCode)-\(script)"
    }
}
