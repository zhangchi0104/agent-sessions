//
//  AppRuntimeModeTests.swift
//  TokenStatsTests
//
//  Guards the unhosted unit-test boundary and the fail-closed behavior that
//  applies if an Xcode configuration ever embeds tests in the app again.
//

import Foundation
import Testing

@MainActor
struct AppRuntimeModeTests {
    @Test func unitTestsRunOutsideTheTokenStatsApplication() {
        #expect(AppRuntimeMode.current == .unitTesting)
        #expect(Bundle.main.bundleIdentifier != "dev.otakuma.TokenStats")
        #expect(ProcessInfo.processInfo.processName != "TokenStats")
    }

    @Test func uiTestingArgumentTakesPrecedenceOverInheritedXCTestState() {
        let mode = AppRuntimeMode.detect(
            arguments: ["TokenStats", "--ui-testing"],
            environment: ["XCTestBundlePath": "/tmp/TokenStatsUITests.xctest"],
            xctestIsLoaded: true
        )

        #expect(mode == .uiTesting)
        #expect(mode.usesInertDependencies)
        #expect(mode.usesIsolatedPersistence)
    }

    @Test func hostedUnitTestsStayHiddenAndInert() {
        let mode = AppRuntimeMode.detect(
            arguments: ["TokenStats"],
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
            xctestIsLoaded: false
        )

        #expect(mode == .unitTesting)
        #expect(mode.usesInertDependencies)
        #expect(mode.usesIsolatedPersistence)
    }

    @Test func ordinaryLaunchUsesProductionDependenciesAndPersistence() {
        let mode = AppRuntimeMode.detect(
            arguments: ["TokenStats"],
            environment: [:],
            xctestIsLoaded: false
        )

        #expect(mode == .production)
        #expect(!mode.usesInertDependencies)
        #expect(!mode.usesIsolatedPersistence)
    }

    @Test func isolatedDefaultsStayInProcessMemory() throws {
        let identifier = try #require(
            UUID(uuidString: "DDB42F34-E7F1-4CD6-8E5E-3A20C304819D")
        )
        let defaults = InMemoryUserDefaults(
            identifier: identifier,
            initialValues: ["launch-override": "isolated"]
        )
        defaults.set("sentinel", forKey: "value")

        #expect(defaults.string(forKey: "value") == "sentinel")
        #expect(defaults.string(forKey: "launch-override") == "isolated")
        #expect(UserDefaults.standard.persistentDomain(forName: defaults.backingSuiteName) == nil)
    }

    @Test func inactiveTranscriptChangesFinishWithoutStartingAWatcher() async {
        var iterator = InactiveTranscriptChangeSource().ticks().makeAsyncIterator()

        #expect(await iterator.next() == nil)
    }
}
