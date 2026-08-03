//
//  LocalizationSettingsTests.swift
//  TokenStatsTests
//

import AppKit
import Foundation
import Testing

@MainActor
struct LocalizationSettingsTests {
    @Test func languagePickerOrderAndSelfNamesRemainStable() {
        #expect(
            AppLanguage.allCases == [
                .system,
                .english,
                .simplifiedChinese,
                .german,
                .french,
                .japanese,
                .russian,
            ])

        let selfNames: [(AppLanguage, String)] = [
            (.english, "English"),
            (.simplifiedChinese, "简体中文"),
            (.german, "Deutsch"),
            (.french, "Français"),
            (.japanese, "日本語"),
            (.russian, "Русский"),
        ]
        for localeLanguage in AppLanguage.allCases where localeLanguage != .system {
            let localizer = AppLocalizer(
                locale: localeLanguage.locale(basedOn: Locale(identifier: "en-US"))
            )
            for (option, expectedName) in selfNames {
                #expect(localizer.localized(option.pickerTitle) == expectedName)
            }
        }
    }

    @Test func defaultsToSystemAndHasNoPendingRestart() {
        withDefaults { defaults in
            let systemLocale = Locale(identifier: "en-US")
            let settings = LocalizationSettings(
                defaults: defaults,
                systemLocale: systemLocale,
                appPreferredLocalization: "en"
            )

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
                systemLocale: Locale(identifier: "en-US"),
                appPreferredLocalization: "en"
            )

            settings.preferredLanguage = .simplifiedChinese

            #expect(defaults.string(forKey: LocalizationSettings.persistenceKey) == "zh-Hans")
            #expect(settings.preferredLanguage == .simplifiedChinese)
            #expect(settings.effectiveLanguage == .system)
            #expect(settings.effectiveLocale.language.languageCode == .english)
            #expect(settings.needsRestart)

            let relaunched = LocalizationSettings(
                defaults: defaults,
                systemLocale: Locale(identifier: "en-US"),
                appPreferredLocalization: "en"
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
                systemLocale: Locale(identifier: "de-DE"),
                appPreferredLocalization: "zh-Hans"
            )

            settings.preferredLanguage = .simplifiedChinese
            #expect(settings.needsRestart)

            settings.preferredLanguage = .english
            #expect(!settings.needsRestart)
            #expect(settings.effectiveLanguage == .english)
            #expect(settings.effectiveLocale.language.languageCode == .english)
            #expect(
                Locale.Components(locale: settings.effectiveLocale)
                    .languageComponents.script == nil
            )
            #expect(settings.effectiveLocale.region == Locale.Region("DE"))
        }
    }

    @Test func unknownStoredLanguageRepairsToSystem() {
        withDefaults { defaults in
            defaults.set("future-language", forKey: LocalizationSettings.persistenceKey)

            let settings = LocalizationSettings(
                defaults: defaults,
                systemLocale: Locale(identifier: "en-GB"),
                appPreferredLocalization: "en"
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
                systemLocale: Locale(identifier: "en-GB"),
                appPreferredLocalization: "en"
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

        for language in AppLanguage.allCases where language != .system {
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

        let expectedLanguageCodes: [AppLanguage: Locale.LanguageCode] = [
            .english: .english,
            .simplifiedChinese: .chinese,
            .german: Locale.LanguageCode("de"),
            .french: Locale.LanguageCode("fr"),
            .japanese: Locale.LanguageCode("ja"),
            .russian: Locale.LanguageCode("ru"),
        ]
        for language in [AppLanguage.german, .french, .japanese, .russian] {
            let effective = language.locale(basedOn: Locale(identifier: "zh-Hans-CN"))
            #expect(effective.language.languageCode == expectedLanguageCodes[language])
            #expect(
                Locale.Components(locale: effective).languageComponents.script == nil
            )
            #expect(effective.region == Locale.Region("CN"))
        }
    }

    @Test func followSystemUsesTheAppsPreferredLocalizationAndPreservesRegionalComponents() {
        withDefaults { defaults in
            var components = Locale.Components(identifier: "en-US")
            components.calendar = .gregorian
            components.currency = Locale.Currency("USD")
            components.numberingSystem = Locale.NumberingSystem("latn")
            components.hourCycle = .oneToTwelve
            components.measurementSystem = .us
            let systemLocale = Locale(components: components)

            let settings = LocalizationSettings(
                defaults: defaults,
                systemLocale: systemLocale,
                appPreferredLocalization: "zh-Hans-CN"
            )

            #expect(settings.effectiveLanguage == .system)
            #expect(settings.effectiveLocale.language.languageCode == .chinese)
            #expect(
                Locale.Components(locale: settings.effectiveLocale)
                    .languageComponents.script == .hanSimplified
            )
            #expect(settings.effectiveLocale.region == systemLocale.region)
            #expect(settings.effectiveLocale.calendar.identifier == systemLocale.calendar.identifier)
            #expect(settings.effectiveLocale.currency == systemLocale.currency)
            #expect(settings.effectiveLocale.numberingSystem == systemLocale.numberingSystem)
            #expect(settings.effectiveLocale.hourCycle == systemLocale.hourCycle)
            #expect(settings.effectiveLocale.measurementSystem == systemLocale.measurementSystem)
        }
    }

    @Test func followSystemFallsBackWhenTheBundleHasNoLanguageLocalization() {
        let systemLocale = Locale(identifier: "en-US-u-hc-h23")

        for appPreferredLocalization in [nil, "Base"] as [String?] {
            let effectiveLocale = AppLanguage.system.locale(
                basedOn: systemLocale,
                appPreferredLocalization: appPreferredLocalization
            )

            #expect(effectiveLocale == systemLocale)
        }
    }

    @Test func expectedLanguageRegionCombinationsRemainIndependent() {
        let cases: [(AppLanguage, Locale, Locale.LanguageCode, Locale.Region)] = [
            (.english, Locale(identifier: "en-US"), .english, Locale.Region("US")),
            (.english, Locale(identifier: "de-DE"), .english, Locale.Region("DE")),
            (.simplifiedChinese, Locale(identifier: "en-US"), .chinese, Locale.Region("US")),
            (.simplifiedChinese, Locale(identifier: "zh-CN"), .chinese, Locale.Region("CN")),
            (.german, Locale(identifier: "en-US"), Locale.LanguageCode("de"), Locale.Region("US")),
            (.german, Locale(identifier: "de-DE"), Locale.LanguageCode("de"), Locale.Region("DE")),
            (.french, Locale(identifier: "en-US"), Locale.LanguageCode("fr"), Locale.Region("US")),
            (.french, Locale(identifier: "fr-FR"), Locale.LanguageCode("fr"), Locale.Region("FR")),
            (.japanese, Locale(identifier: "en-US"), Locale.LanguageCode("ja"), Locale.Region("US")),
            (.japanese, Locale(identifier: "ja-JP"), Locale.LanguageCode("ja"), Locale.Region("JP")),
            (.russian, Locale(identifier: "en-US"), Locale.LanguageCode("ru"), Locale.Region("US")),
            (.russian, Locale(identifier: "ru-RU"), Locale.LanguageCode("ru"), Locale.Region("RU")),
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

        for language in ["de", "fr", "ja", "ru"] {
            let locale = Locale(identifier: "\(language)-US-u-nu-latn")
            #expect(AppLocalizer(locale: locale).htmlLanguageTag == language)
        }
    }

    @Test func everyExplicitLanguageRawValuePersistsAndRelaunches() {
        for language in AppLanguage.allCases where language != .system {
            withDefaults { defaults in
                let initial = LocalizationSettings(
                    defaults: defaults,
                    systemLocale: Locale(identifier: "en-US"),
                    appPreferredLocalization: "en"
                )

                initial.preferredLanguage = language
                #expect(defaults.string(forKey: LocalizationSettings.persistenceKey) == language.rawValue)
                #expect(initial.needsRestart)

                let relaunched = LocalizationSettings(
                    defaults: defaults,
                    systemLocale: Locale(identifier: "en-US"),
                    appPreferredLocalization: "en"
                )
                #expect(relaunched.effectiveLanguage == language)
                #expect(
                    relaunched.effectiveLocale.language.languageCode
                        == language.locale(basedOn: Locale(identifier: "en-US")).language.languageCode)
                #expect(!relaunched.needsRestart)
            }
        }
    }

    private func withDefaults(_ test: (UserDefaults) -> Void) {
        test(InMemoryUserDefaults())
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

    @Test func testingRelauncherFailsClosedAndKeepsTheCurrentInstanceRunning() {
        let relauncher = AppRelauncher.disabledForTesting()

        relauncher.relaunch()

        #expect(!relauncher.isRelaunching)
        #expect(relauncher.failure == .newInstanceLaunchFailed)
    }
}
