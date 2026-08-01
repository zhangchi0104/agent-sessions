//
//  LocalizationSettingsTests.swift
//  TokenStatsTests
//

import AppKit
import Foundation
import Testing
@testable import TokenStats

@MainActor
struct LocalizationSettingsTests {
    @Test func defaultsToSystemAndHasNoPendingRestart() {
        withDefaults { defaults in
            let systemLocale = Locale(identifier: "en-US")
            let settings = LocalizationSettings(defaults: defaults, systemLocale: systemLocale)

            #expect(settings.preferredLanguage == .system)
            #expect(settings.effectiveLanguage == .system)
            #expect(settings.effectiveLocale == systemLocale)
            #expect(!settings.needsRestart)
        }
    }

    @Test func preferencePersistsButEffectiveLanguageIsFrozenUntilRelaunch() {
        withDefaults { defaults in
            let settings = LocalizationSettings(
                defaults: defaults,
                systemLocale: Locale(identifier: "en-US")
            )

            settings.preferredLanguage = .simplifiedChinese

            #expect(defaults.string(forKey: LocalizationSettings.persistenceKey) == "zh-Hans")
            #expect(settings.preferredLanguage == .simplifiedChinese)
            #expect(settings.effectiveLanguage == .system)
            #expect(settings.effectiveLocale.language.languageCode == .english)
            #expect(settings.needsRestart)

            let relaunched = LocalizationSettings(
                defaults: defaults,
                systemLocale: Locale(identifier: "en-US")
            )
            #expect(relaunched.effectiveLanguage == .simplifiedChinese)
            #expect(relaunched.effectiveLocale.language.languageCode == .chinese)
            #expect(relaunched.effectiveLocale.language.script == .hanSimplified)
            #expect(!relaunched.needsRestart)
        }
    }

    @Test func selectingTheEffectiveLanguageAgainCancelsThePendingRestart() {
        withDefaults { defaults in
            defaults.set(AppLanguage.english.rawValue, forKey: LocalizationSettings.persistenceKey)
            let settings = LocalizationSettings(
                defaults: defaults,
                systemLocale: Locale(identifier: "de-DE")
            )

            settings.preferredLanguage = .simplifiedChinese
            #expect(settings.needsRestart)

            settings.preferredLanguage = .english
            #expect(!settings.needsRestart)
            #expect(settings.effectiveLanguage == .english)
        }
    }

    @Test func unknownStoredLanguageRepairsToSystem() {
        withDefaults { defaults in
            defaults.set("future-language", forKey: LocalizationSettings.persistenceKey)

            let settings = LocalizationSettings(
                defaults: defaults,
                systemLocale: Locale(identifier: "en-GB")
            )

            #expect(settings.preferredLanguage == .system)
            #expect(settings.effectiveLanguage == .system)
            #expect(defaults.object(forKey: LocalizationSettings.persistenceKey) == nil)
            #expect(!settings.needsRestart)
        }
    }

    @Test func nonStringStoredLanguageAlsoRepairsToSystem() {
        withDefaults { defaults in
            defaults.set(["unexpected"], forKey: LocalizationSettings.persistenceKey)

            let settings = LocalizationSettings(
                defaults: defaults,
                systemLocale: Locale(identifier: "en-GB")
            )

            #expect(settings.preferredLanguage == .system)
            #expect(settings.effectiveLanguage == .system)
            #expect(defaults.object(forKey: LocalizationSettings.persistenceKey) == nil)
        }
    }

    @Test func languageOverridesPreserveSystemRegionalComponents() {
        var components = Locale.Components(identifier: "de-DE")
        components.calendar = .gregorian
        components.currency = Locale.Currency("EUR")
        components.numberingSystem = Locale.NumberingSystem("arab")
        components.hourCycle = .zeroToTwentyThree
        components.measurementSystem = .metric
        let systemLocale = Locale(components: components)

        for language in [AppLanguage.english, .simplifiedChinese] {
            let locale = language.locale(basedOn: systemLocale)

            #expect(locale.region == systemLocale.region)
            #expect(locale.calendar.identifier == systemLocale.calendar.identifier)
            #expect(locale.currency == systemLocale.currency)
            #expect(locale.numberingSystem == systemLocale.numberingSystem)
            #expect(locale.hourCycle == systemLocale.hourCycle)
            #expect(locale.measurementSystem == systemLocale.measurementSystem)
        }

        let english = AppLanguage.english.locale(basedOn: systemLocale)
        #expect(english.language.languageCode == .english)
        #expect(Locale.Components(locale: english).languageComponents.script == nil)

        let chinese = AppLanguage.simplifiedChinese.locale(basedOn: systemLocale)
        #expect(chinese.language.languageCode == .chinese)
        #expect(chinese.language.script == .hanSimplified)
    }

    @Test func expectedLanguageRegionCombinationsRemainIndependent() {
        let cases: [(AppLanguage, Locale, Locale.LanguageCode, Locale.Region)] = [
            (.english, Locale(identifier: "en-US"), .english, Locale.Region("US")),
            (.english, Locale(identifier: "de-DE"), .english, Locale.Region("DE")),
            (.simplifiedChinese, Locale(identifier: "en-US"), .chinese, Locale.Region("US")),
            (.simplifiedChinese, Locale(identifier: "zh-CN"), .chinese, Locale.Region("CN")),
        ]

        for (language, systemLocale, expectedLanguage, expectedRegion) in cases {
            let effective = language.locale(basedOn: systemLocale)
            #expect(effective.language.languageCode == expectedLanguage)
            #expect(effective.region == expectedRegion)
        }
    }

    @Test func appLocalizerUsesItsExplicitLocaleAndProvidesAnHTMLLanguageTag() {
        let localizer = AppLocalizer(locale: Locale(identifier: "zh-Hans-CN-u-nu-latn"))
        let resource = LocalizedStringResource(
            "tests.localization.default-value",
            defaultValue: "Default value",
            comment: "Test-only fallback copy."
        )

        #expect(localizer.resource(resource).locale == localizer.locale)
        #expect(localizer.localized(resource) == "Default value")
        #expect(localizer.htmlLanguageTag == "zh-Hans")
    }

    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "TokenStatsTests.Localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        test(defaults)
    }
}

@MainActor
struct AppRelauncherTests {
    @Test func successfulReplacementLaunchTerminatesTheCurrentInstance() {
        let expectedURL = URL(fileURLWithPath: "/Applications/TokenStats.app")
        var launchedURL: URL?
        var requestedNewInstance = false
        var terminationCount = 0

        let relauncher = AppRelauncher(
            applicationURL: { expectedURL },
            launchNewInstance: { url, configuration, completion in
                launchedURL = url
                requestedNewInstance = configuration.createsNewApplicationInstance
                completion(true)
            },
            terminateCurrentInstance: { terminationCount += 1 }
        )

        relauncher.relaunch()

        #expect(launchedURL == expectedURL)
        #expect(requestedNewInstance)
        #expect(terminationCount == 1)
        #expect(!relauncher.isRelaunching)
        #expect(relauncher.failure == nil)
    }

    @Test func failedReplacementLaunchKeepsTheCurrentInstanceRunning() {
        var terminationCount = 0
        let relauncher = AppRelauncher(
            applicationURL: { URL(fileURLWithPath: "/Applications/TokenStats.app") },
            launchNewInstance: { _, _, completion in completion(false) },
            terminateCurrentInstance: { terminationCount += 1 }
        )

        relauncher.relaunch()

        #expect(terminationCount == 0)
        #expect(!relauncher.isRelaunching)
        #expect(relauncher.failure == .newInstanceLaunchFailed)
    }

    @Test func missingApplicationURLDoesNotAttemptLaunchOrTermination() {
        var launchCount = 0
        var terminationCount = 0
        let relauncher = AppRelauncher(
            applicationURL: { nil },
            launchNewInstance: { _, _, _ in launchCount += 1 },
            terminateCurrentInstance: { terminationCount += 1 }
        )

        relauncher.relaunch()

        #expect(launchCount == 0)
        #expect(terminationCount == 0)
        #expect(relauncher.failure == .applicationURLUnavailable)
    }

    @Test func repeatedRequestsAreIgnoredWhileLaunchIsInProgress() {
        var launchCount = 0
        var pendingCompletion: (@MainActor (Bool) -> Void)?
        let relauncher = AppRelauncher(
            applicationURL: { URL(fileURLWithPath: "/Applications/TokenStats.app") },
            launchNewInstance: { _, _, completion in
                launchCount += 1
                pendingCompletion = completion
            },
            terminateCurrentInstance: {}
        )

        relauncher.relaunch()
        relauncher.relaunch()

        #expect(launchCount == 1)
        #expect(relauncher.isRelaunching)

        pendingCompletion?(false)
        #expect(!relauncher.isRelaunching)
        #expect(relauncher.failure == .newInstanceLaunchFailed)
    }

    @Test func uiTestingRelauncherFailsClosedAndKeepsTheCurrentInstanceRunning() {
        let relauncher = AppRelauncher.disabledForUITesting()

        relauncher.relaunch()

        #expect(!relauncher.isRelaunching)
        #expect(relauncher.failure == .newInstanceLaunchFailed)
    }
}
