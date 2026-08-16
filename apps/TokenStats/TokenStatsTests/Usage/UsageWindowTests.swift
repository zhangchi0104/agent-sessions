//
//  UsageWindowTests.swift
//  TokenStatsTests
//
//  Persistence and presentation-independent identity for Usage Windows.
//

import Foundation
import Testing

struct UsageWindowTests {

    @Test func semanticIdentitiesRoundTripWithoutPersistingDisplayLabels() throws {
        let identities: [UsageWindowIdentity] = [
            .shortTerm,
            .weekly,
            .cursorModels,
            .otherModels,
            .modelWeekly(model: "Fable"),
            .duration(seconds: 7_200),
            .provider(raw: "Provider special"),
        ]

        for identity in identities {
            let window = UsageWindow(identity: identity, percentConsumed: 42, resetAt: nil)
            let encoded = try JSONEncoder().encode(window)
            let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

            #expect(object["identity"] != nil)
            #expect(object["label"] == nil)
            #expect(try JSONDecoder().decode(UsageWindow.self, from: encoded) == window)
        }
    }

    @Test func decodesKnownLegacyLabelsAsSemanticIdentities() throws {
        let cases: [(String, UsageWindowIdentity)] = [
            ("5-hour", .shortTerm),
            ("Weekly", .weekly),
            ("Cursor Models", .cursorModels),
            ("Other Models", .otherModels),
            ("Fable", .modelWeekly(model: "Fable")),
        ]

        for (label, expected) in cases {
            let window = try decodeLegacyWindow(label: label)

            #expect(window.identity == expected)
        }
    }

    @Test func decodesLegacyDurationLabelsWithoutKeepingEnglishAsIdentity() throws {
        let cases: [(String, Int)] = [
            ("3-day", 3 * 24 * 60 * 60),
            ("2-hour", 2 * 60 * 60),
            ("15-minute", 15 * 60),
            ("45-second", 45),
        ]

        for (label, seconds) in cases {
            let window = try decodeLegacyWindow(label: label)

            #expect(window.identity == .duration(seconds: seconds))
            #expect(window.label == label)
        }
    }

    @Test func preservesUnknownLegacyProviderLabelsVerbatim() throws {
        let window = try decodeLegacyWindow(label: "Provider special")

        #expect(window.identity == .provider(raw: "Provider special"))
        #expect(window.label == "Provider special")
    }

    @Test func normalizesWellKnownReportedDurations() {
        #expect(UsageWindowIdentity.reportedDuration(seconds: 18_000) == .shortTerm)
        #expect(UsageWindowIdentity.reportedDuration(seconds: 604_800) == .weekly)
        #expect(UsageWindowIdentity.reportedDuration(seconds: 7_200) == .duration(seconds: 7_200))
    }

    @Test func localizesSemanticAndDurationTitlesForEnglishAndSimplifiedChinese() {
        let cases = [
            (
                locale: "en-US",
                shortTerm: "5-hour",
                weekly: "Weekly",
                cursorModels: "Cursor Models",
                otherModels: "Other Models",
                duration: "2 hours"
            ),
            (
                locale: "zh-Hans-CN",
                shortTerm: "5 小时",
                weekly: "每周",
                cursorModels: "Cursor 模型",
                otherModels: "其他模型",
                duration: "2小时"
            ),
        ]

        for expected in cases {
            let localizer = AppLocalizer(locale: Locale(identifier: expected.locale))

            #expect(UsageWindowIdentity.shortTerm.localizedTitle(using: localizer) == expected.shortTerm)
            #expect(UsageWindowIdentity.weekly.localizedTitle(using: localizer) == expected.weekly)
            #expect(
                UsageWindowIdentity.cursorModels.localizedTitle(using: localizer) == expected.cursorModels
            )
            #expect(
                UsageWindowIdentity.otherModels.localizedTitle(using: localizer) == expected.otherModels
            )
            #expect(
                UsageWindowIdentity.duration(seconds: 2 * 60 * 60)
                    .localizedTitle(using: localizer) == expected.duration
            )
        }
    }

    private func decodeLegacyWindow(label: String) throws -> UsageWindow {
        let labelData = try JSONEncoder().encode(label)
        let encodedLabel = try #require(String(data: labelData, encoding: .utf8))
        let data = Data(
            #"{"label":\#(encodedLabel),"percentConsumed":42}"#.utf8
        )
        return try JSONDecoder().decode(UsageWindow.self, from: data)
    }
}
