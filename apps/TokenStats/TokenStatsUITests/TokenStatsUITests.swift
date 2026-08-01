//
//  TokenStatsUITests.swift
//  TokenStatsUITests
//

import XCTest

final class TokenStatsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEnglishOnboardingUsesStableIdentifier() throws {
        let app = launch(language: "en")
        let title = app.staticTexts["onboarding.welcome.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Welcome to TokenStats")
    }

    @MainActor
    func testSimplifiedChineseOnboardingUsesStableIdentifier() throws {
        let app = launch(language: "zh-Hans")
        let title = app.staticTexts["onboarding.welcome.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "欢迎使用 TokenStats")
    }

    @MainActor
    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-localization.preferredLanguage", language,
        ]
        app.launch()
        return app
    }
}
