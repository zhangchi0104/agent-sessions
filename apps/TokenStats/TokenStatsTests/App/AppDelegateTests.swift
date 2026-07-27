//
//  AppDelegateTests.swift
//  TokenStatsTests
//
//  The test bundle is hosted by the app itself, under the shipped bundle id.
//  If the delegate's launch work ran during a test it would read the real
//  Keychain accounts, call both usage endpoints, and overwrite the persisted
//  snapshot — and on a fresh CI runner it would present the onboarding window.
//  This asserts the detection that suppresses all of it actually fires.
//

import Testing
@testable import TokenStats

@MainActor
struct AppDelegateTests {

    @Test func theTestHostRecognisesItIsRunningTests() {
        // If this ever reads false, applicationDidFinishLaunching starts doing
        // real work on every `npm test` — including on a contributor's machine.
        #expect(AppDelegate.isRunningUnitTests)
    }
}
