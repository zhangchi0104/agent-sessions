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
    func testGermanOnboardingUsesStableIdentifier() throws {
        let app = launch(language: "de")
        let title = app.staticTexts["onboarding.welcome.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Willkommen bei TokenStats")
    }

    @MainActor
    func testFrenchOnboardingUsesStableIdentifier() throws {
        let app = launch(language: "fr")
        let title = app.staticTexts["onboarding.welcome.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Bienvenue dans TokenStats")
    }

    @MainActor
    func testJapaneseOnboardingUsesStableIdentifier() throws {
        let app = launch(language: "ja")
        let title = app.staticTexts["onboarding.welcome.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "TokenStats へようこそ")
    }

    @MainActor
    func testRussianOnboardingUsesStableIdentifier() throws {
        let app = launch(language: "ru")
        let title = app.staticTexts["onboarding.welcome.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Добро пожаловать в TokenStats")
    }

    @MainActor
    func testTokenSummaryHeroHeightIsStableAcrossRangesAndValueLengths() throws {
        let app = launch(
            language: "en",
            extraArguments: ["--ui-testing-token-summary-layout"]
        )

        let identifiers = [
            "tokens.summary.hero.today-short",
            "tokens.summary.hero.seven-days-large",
            "tokens.summary.hero.thirty-days-very-large",
        ]
        var heights: [CGFloat] = []

        for identifier in identifiers {
            let hero = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(
                hero.waitForExistence(timeout: 5),
                "Missing TokenSummaryHero fixture: \(identifier)"
            )

            let frame = waitForFrame(
                of: hero,
                width: 300,
                height: 88,
                identifier: identifier
            )
            XCTAssertFalse(frame.isEmpty, "Empty TokenSummaryHero frame: \(identifier)")
            XCTAssertEqual(frame.width, 300, accuracy: 1, identifier)
            XCTAssertEqual(frame.height, 88, accuracy: 1, identifier)
            heights.append(frame.height)
        }

        let shortest = try XCTUnwrap(heights.min())
        let tallest = try XCTUnwrap(heights.max())
        XCTAssertEqual(tallest, shortest, accuracy: 1)
    }

    @MainActor
    private func launch(
        language: String,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-localization.preferredLanguage", language,
        ] + extraArguments
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    @MainActor
    private func waitForFrame(
        of element: XCUIElement,
        width: CGFloat,
        height: CGFloat,
        identifier: String
    ) -> CGRect {
        let deadline = Date().addingTimeInterval(5)
        var frame = element.frame
        while Date() < deadline {
            frame = element.frame
            if !frame.isEmpty
                && abs(frame.width - width) <= 1
                && abs(frame.height - height) <= 1 {
                return frame
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail(
            "TokenSummaryHero frame did not settle: \(identifier); "
                + "observed \(frame), expected \(width)x\(height)"
        )
        return frame
    }
}
