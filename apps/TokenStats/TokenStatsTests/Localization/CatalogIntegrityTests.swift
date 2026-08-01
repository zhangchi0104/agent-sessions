//
//  CatalogIntegrityTests.swift
//  TokenStatsTests
//
//  The first-party languages are release-complete: every semantic key carries
//  review context and an explicitly translated English and Simplified Chinese
//  value. This reads the source catalog so a fallback cannot hide a missing
//  localization in the compiled bundle.
//

import Foundation
import Testing

struct CatalogIntegrityTests {
    private static let requiredLanguages = ["en", "zh-Hans"]

    /// Count-dependent sentences must keep their plural contract explicit. A
    /// new count key belongs here so review cannot accidentally rely on the
    /// existence of some unrelated plural elsewhere in the catalog.
    private static let requiredPluralKeys: Set<String> = [
        "onboarding.done.connected_agents.summary",
        "tokens.agent.selected_total.accessibility",
        "tokens.agent.selected_total.help",
        "tokens.summary.api_equivalent.partial.help",
        "tokens.summary.billing.accessibility",
        "tokens.summary.billing.help",
    ]

    /// SwiftUI may ask Xcode to extract non-linguistic display symbols. They do
    /// not represent copy and intentionally have no localized variants.
    private static let allowedNonSemanticKeys: Set<String> = ["—"]

    @Test func everySemanticKeyHasReviewedEnglishAndSimplifiedChineseCopy() throws {
        let catalog = try sourceCatalog()
        #expect(catalog.sourceLanguage == "en")
        #expect(catalog.version == "1.0")
        #expect(catalog.strings.isEmpty == false)

        let unexpectedKeys = catalog.strings.keys.filter {
            Self.isSemanticKey($0) == false && Self.allowedNonSemanticKeys.contains($0) == false
        }
        #expect(
            unexpectedKeys.isEmpty,
            "String Catalog contains non-semantic keys: \(unexpectedKeys.sorted())"
        )

        for key in catalog.strings.keys.sorted() where Self.isSemanticKey(key) {
            let entry = try #require(catalog.strings[key])
            #expect(
                entry.comment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                "\(key) needs a translator comment"
            )

            let localizations = try #require(
                entry.localizations,
                "\(key) has no localizations"
            )
            for language in Self.requiredLanguages {
                let localization = try #require(
                    localizations[language],
                    "\(key) is missing \(language)"
                )
                let units = Self.stringUnits(in: localization)
                #expect(
                    units.isEmpty == false,
                    "\(key) has no translated String Unit for \(language)"
                )
                for unit in units {
                    #expect(
                        unit.state == "translated",
                        "\(key) must be reviewed as translated for \(language), found \(unit.state)"
                    )
                    let value = unit.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    #expect(value.isEmpty == false, "\(key) has an empty \(language) value")
                    #expect(value != key, "\(key) would expose its key at runtime for \(language)")
                }
            }
        }
    }

    @Test func nonSemanticCatalogEntriesAreLimitedToDocumentedSymbols() throws {
        let catalog = try sourceCatalog()
        let actual = Set(catalog.strings.keys.filter { Self.isSemanticKey($0) == false })
        #expect(actual.isSubset(of: Self.allowedNonSemanticKeys))

        for key in actual {
            let entry = try #require(catalog.strings[key])
            #expect(
                entry.localizations?.isEmpty != false,
                "Non-linguistic key \(key) must not carry translated UI copy"
            )
        }
    }

    @Test func everyPluralVariationDefinesOneAndOtherCategories() throws {
        let catalog = try sourceCatalog()
        var pluralKeys: Set<String> = []

        for key in catalog.strings.keys.sorted() where Self.isSemanticKey(key) {
            let entry = try #require(catalog.strings[key])
            for language in Self.requiredLanguages {
                guard let localization = entry.localizations?[language] else { continue }
                for categories in Self.pluralCategorySets(in: localization) {
                    pluralKeys.insert(key)
                    #expect(
                        categories.isSuperset(of: ["one", "other"]),
                        "\(key) must define one/other plural categories for \(language); found \(categories.sorted())"
                    )
                }
            }
        }

        #expect(
            pluralKeys == Self.requiredPluralKeys,
            "Plural keys changed. Expected \(Self.requiredPluralKeys.sorted()), found \(pluralKeys.sorted())"
        )

        for key in Self.requiredPluralKeys.sorted() {
            let entry = try #require(catalog.strings[key], "Missing required plural key \(key)")
            for language in Self.requiredLanguages {
                let localization = try #require(
                    entry.localizations?[language],
                    "\(key) is missing plural localization for \(language)"
                )
                let categorySets = Self.pluralCategorySets(in: localization)
                #expect(
                    categorySets.isEmpty == false,
                    "\(key) must define a plural variation for \(language)"
                )
                for categories in categorySets {
                    #expect(
                        categories.isSuperset(of: ["one", "other"]),
                        "\(key) must define one/other plural categories for \(language); found \(categories.sorted())"
                    )
                }
            }
        }
    }

    @Test func placeholdersMatchAcrossLanguagesAndPluralBranches() throws {
        let catalog = try sourceCatalog()

        for key in catalog.strings.keys.sorted() where Self.isSemanticKey(key) {
            let entry = try #require(catalog.strings[key])
            let localizations = try #require(entry.localizations, "\(key) has no localizations")
            let english = try #require(localizations["en"], "\(key) is missing en")
            let simplifiedChinese = try #require(
                localizations["zh-Hans"],
                "\(key) is missing zh-Hans"
            )

            let englishUnits = Self.stringUnitsByPath(in: english)
            let chineseUnits = Self.stringUnitsByPath(in: simplifiedChinese)
            #expect(
                Set(englishUnits.keys) == Set(chineseUnits.keys),
                "\(key) must have corresponding en/zh-Hans String Unit leaves"
            )
            for path in Set(englishUnits.keys).intersection(Set(chineseUnits.keys)).sorted() {
                let englishValue = try #require(englishUnits[path]?.value)
                let chineseValue = try #require(chineseUnits[path]?.value)
                #expect(
                    Self.printfPlaceholders(in: englishValue)
                        == Self.printfPlaceholders(in: chineseValue),
                    "\(key) leaf \(path) changed placeholder positions/types between en and zh-Hans"
                )
            }

            for language in Self.requiredLanguages {
                let localization = try #require(localizations[language])
                for branch in Self.pluralBranches(in: localization) {
                    let one = try #require(
                        branch.categories["one"],
                        "\(key) plural \(branch.path) is missing one for \(language)"
                    )
                    let other = try #require(
                        branch.categories["other"],
                        "\(key) plural \(branch.path) is missing other for \(language)"
                    )
                    let oneUnits = Self.stringUnitsByPath(in: one)
                    let otherUnits = Self.stringUnitsByPath(in: other)
                    #expect(
                        Set(oneUnits.keys) == Set(otherUnits.keys),
                        "\(key) plural \(branch.path) must have corresponding one/other leaves for \(language)"
                    )
                    for path in Set(oneUnits.keys).intersection(Set(otherUnits.keys)).sorted() {
                        let oneValue = try #require(oneUnits[path]?.value)
                        let otherValue = try #require(otherUnits[path]?.value)
                        #expect(
                            Self.printfPlaceholders(in: oneValue)
                                == Self.printfPlaceholders(in: otherValue),
                            "\(key) plural \(branch.path)/\(path) changed placeholder positions/types between one and other for \(language)"
                        )
                    }
                }
            }
        }
    }

    private func sourceCatalog() throws -> SourceCatalog {
        let appDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Localization
            .deletingLastPathComponent() // TokenStatsTests
            .deletingLastPathComponent() // apps/TokenStats
        let url = appDirectory.appendingPathComponent("TokenStats/Localizable.xcstrings")
        return try JSONDecoder().decode(SourceCatalog.self, from: Data(contentsOf: url))
    }

    private static func isSemanticKey(_ key: String) -> Bool {
        key.range(
            of: #"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func stringUnits(in value: JSONValue) -> [StringUnit] {
        Array(stringUnitsByPath(in: value).values)
    }

    private static func stringUnitsByPath(
        in value: JSONValue,
        path: [String] = []
    ) -> [String: StringUnit] {
        switch value {
        case .object(let object):
            var units: [String: StringUnit] = [:]
            if case .object(let rawUnit)? = object["stringUnit"],
               case .string(let state)? = rawUnit["state"],
               case .string(let value)? = rawUnit["value"] {
                units[path.joined(separator: "/")] = StringUnit(state: state, value: value)
            }
            for (key, child) in object {
                units.merge(
                    stringUnitsByPath(in: child, path: path + [key]),
                    uniquingKeysWith: { first, _ in first }
                )
            }
            return units
        case .array(let values):
            var units: [String: StringUnit] = [:]
            for (index, child) in values.enumerated() {
                units.merge(
                    stringUnitsByPath(in: child, path: path + [String(index)]),
                    uniquingKeysWith: { first, _ in first }
                )
            }
            return units
        case .string, .number, .boolean, .null:
            return [:]
        }
    }

    private static func pluralBranches(
        in value: JSONValue,
        path: [String] = []
    ) -> [PluralBranch] {
        switch value {
        case .object(let object):
            var branches: [PluralBranch] = []
            if case .object(let variations)? = object["variations"],
               case .object(let plural)? = variations["plural"] {
                branches.append(PluralBranch(
                    path: path.joined(separator: "/"),
                    categories: plural
                ))
            }
            for (key, child) in object {
                branches += pluralBranches(in: child, path: path + [key])
            }
            return branches
        case .array(let values):
            return values.enumerated().flatMap { index, child in
                pluralBranches(in: child, path: path + [String(index)])
            }
        case .string, .number, .boolean, .null:
            return []
        }
    }

    /// Returns a canonical placeholder schema sorted by argument position. A
    /// translator may reorder `%1$@` and `%2$@` in the sentence, but may not
    /// drop an argument or change (for example) `%1$lld` into `%1$@`.
    private static func printfPlaceholders(in value: String) -> [PrintfPlaceholder] {
        let expression = try! NSRegularExpression(
            pattern: #"%(?:(\d+)\$)?(hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfeEgGcCsSpaA])"#
        )
        let source = value as NSString
        let matches = expression.matches(
            in: value,
            range: NSRange(location: 0, length: source.length)
        )
        return matches.enumerated().map { index, match in
            let explicitPosition: Int?
            if match.range(at: 1).location == NSNotFound {
                explicitPosition = nil
            } else {
                explicitPosition = Int(source.substring(with: match.range(at: 1)))
            }
            let lengthModifier = match.range(at: 2).location == NSNotFound
                ? ""
                : source.substring(with: match.range(at: 2))
            let conversion = source.substring(with: match.range(at: 3))
            return PrintfPlaceholder(
                position: explicitPosition ?? index + 1,
                type: lengthModifier + conversion
            )
        }
        .sorted {
            if $0.position != $1.position {
                return $0.position < $1.position
            }
            return $0.type < $1.type
        }
    }

    private static func pluralCategorySets(in value: JSONValue) -> [Set<String>] {
        switch value {
        case .object(let object):
            var categorySets: [Set<String>] = []
            if case .object(let variations)? = object["variations"],
               case .object(let plural)? = variations["plural"] {
                categorySets.append(Set(plural.keys))
            }
            return categorySets + object.values.flatMap(pluralCategorySets(in:))
        case .array(let values):
            return values.flatMap(pluralCategorySets(in:))
        case .string, .number, .boolean, .null:
            return []
        }
    }
}

private struct SourceCatalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogEntry]
    let version: String
}

private struct CatalogEntry: Decodable {
    let comment: String?
    let localizations: [String: JSONValue]?
}

private struct StringUnit {
    let state: String
    let value: String
}

private struct PluralBranch {
    let path: String
    let categories: [String: JSONValue]
}

private struct PrintfPlaceholder: Equatable {
    let position: Int
    let type: String
}

private enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }
}
