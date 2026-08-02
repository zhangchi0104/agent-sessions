//
//  CurrencyTypes.swift
//  TokenStats
//
//  Pure local-currency presentation types. USD remains the pricing domain;
//  these values describe only how an exact USD aggregate is shown.
//

import Foundation

nonisolated struct CurrencyCode: RawRepresentable, Hashable, Comparable, Sendable {
    let rawValue: String

    init?(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.utf8.count == 3,
              normalized.utf8.allSatisfy({ $0 >= 65 && $0 <= 90 }),
              Self.knownCodes.contains(normalized)
        else { return nil }
        rawValue = normalized
    }

    init?(rawValue: String) {
        self.init(rawValue)
    }

    static let usd = CurrencyCode(unchecked: "USD")

    static func < (lhs: CurrencyCode, rhs: CurrencyCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private init(unchecked value: String) {
        rawValue = value
    }

    private static let knownCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))
}

nonisolated extension CurrencyCode: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let code = CurrencyCode(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 4217 currency code: \(value)"
            )
        }
        self = code
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated enum DisplayCurrencySelection: Equatable, Sendable {
    case system
    case fixed(CurrencyCode)
}

nonisolated extension DisplayCurrencySelection: Codable {
    private enum CodingKeys: String, CodingKey { case mode, code }
    private enum Mode: String, Codable { case system, fixed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .system:
            self = .system
        case .fixed:
            self = .fixed(try container.decode(CurrencyCode.self, forKey: .code))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .system:
            try container.encode(Mode.system, forKey: .mode)
        case let .fixed(code):
            try container.encode(Mode.fixed, forKey: .mode)
            try container.encode(code, forKey: .code)
        }
    }
}

nonisolated struct ExchangeRateQuote: Codable, Equatable, Sendable {
    let quoteCode: CurrencyCode
    let rate: Decimal
    let rateDate: Date
}

nonisolated struct ExchangeRateSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let baseCode: CurrencyCode
    let source: ExchangeRateSource
    let fetchedAt: Date
    let quotes: [ExchangeRateQuote]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        baseCode: CurrencyCode = .usd,
        source: ExchangeRateSource = .default,
        fetchedAt: Date,
        quotes: [ExchangeRateQuote]
    ) {
        self.schemaVersion = schemaVersion
        self.baseCode = baseCode
        self.source = source
        self.fetchedAt = fetchedAt
        self.quotes = quotes.sorted { $0.quoteCode < $1.quoteCode }
    }

    func quote(for code: CurrencyCode) -> ExchangeRateQuote? {
        quotes.first { $0.quoteCode == code }
    }

    var isValidEnvelope: Bool {
        schemaVersion == Self.currentSchemaVersion
            && baseCode == .usd
            && source.isValid
            && !quotes.isEmpty
            && Set(quotes.map(\.quoteCode)).count == quotes.count
            && quotes.allSatisfy { $0.rate > 0 && $0.quoteCode != .usd }
    }
}

nonisolated enum ExchangeRateAttemptOutcome: String, Codable, Equatable, Sendable {
    case pending
    case success
    case failure
}

nonisolated struct ExchangeRateAttempt: Codable, Equatable, Sendable {
    let attemptedAt: Date
    let outcome: ExchangeRateAttemptOutcome
    let errorDescription: String?
    let source: ExchangeRateSource

    init(
        attemptedAt: Date,
        outcome: ExchangeRateAttemptOutcome,
        errorDescription: String?,
        source: ExchangeRateSource = .default
    ) {
        self.attemptedAt = attemptedAt
        self.outcome = outcome
        self.errorDescription = errorDescription
        self.source = source
    }
}

nonisolated struct CurrencyDisplayAmount: Equatable, Sendable {
    let exactUSD: Decimal
    let exactValue: Decimal
    let roundedValue: Decimal
    let currencyCode: CurrencyCode
    let localeIdentifier: String

    var numericValue: Double {
        NSDecimalNumber(decimal: roundedValue).doubleValue
    }

    func formatted(compact: Bool = false) -> String {
        let locale = Locale(identifier: localeIdentifier)
        let fractionDigits = CurrencyAmountFormatting.minorUnits(for: currencyCode)
        let magnitude = abs(NSDecimalNumber(decimal: roundedValue).doubleValue)
        // Preserve the existing USD contract used by the pricing domain and
        // its fixtures. Runtime system/fixed selections use their real locale;
        // only the explicit POSIX compatibility context takes this path.
        if currencyCode == .usd, localeIdentifier == "en_US_POSIX" {
            return CurrencyAmountFormatting.posixUSD(
                roundedValue,
                compact: compact && magnitude >= 1_000_000
            )
        }
        if compact, magnitude >= 1_000_000 {
            if #available(macOS 15.0, *) {
                return roundedValue.formatted(
                    .currency(code: currencyCode.rawValue)
                        .notation(.compactName)
                        .precision(.fractionLength(0...1))
                        .locale(locale)
                )
            }
            return CurrencyAmountFormatting.legacyCompact(
                roundedValue,
                currencyCode: currencyCode,
                locale: locale
            )
        }
        return roundedValue.formatted(
            .currency(code: currencyCode.rawValue)
                .precision(.fractionLength(fractionDigits))
                .locale(locale)
        )
    }
}

nonisolated struct CurrencyDisplayContext: Equatable, Sendable {
    /// The user's resolved selection. This can differ from `currencyCode` when
    /// the selected quote is unavailable and the UI must fall back to USD.
    let requestedCode: CurrencyCode
    let currencyCode: CurrencyCode
    let rate: Decimal
    let rateDate: Date?
    let fetchedAt: Date?
    let isStale: Bool
    let isFallback: Bool
    let localeIdentifier: String

    static let usd = CurrencyDisplayContext(
        requestedCode: .usd,
        currencyCode: .usd,
        rate: 1,
        rateDate: nil,
        fetchedAt: nil,
        isStale: false,
        isFallback: false,
        localeIdentifier: "en_US_POSIX"
    )

    func amount(forUSD exactUSD: Decimal) -> CurrencyDisplayAmount {
        let exactValue = exactUSD * rate
        return CurrencyDisplayAmount(
            exactUSD: exactUSD,
            exactValue: exactValue,
            roundedValue: CurrencyAmountFormatting.roundUp(
                exactValue,
                currencyCode: currencyCode
            ),
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
    }
}

nonisolated enum CurrencyAmountFormatting {
    /// Provider quote dates are normalized to a UTC instant. Render the date in
    /// UTC so negative-offset user time zones cannot shift it to the previous
    /// local day.
    static func rateDateText(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func posixUSD(_ value: Decimal, compact: Bool) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        if compact {
            let units: [(Double, String)] = [(1e9, "B"), (1e6, "M")]
            if let (unit, suffix) = units.first(where: { abs(number) >= $0.0 }) {
                let scaled = number / unit
                let text = abs(scaled) < 9.95
                    ? String(format: "%.1f", scaled)
                    : String(format: "%.0f", scaled)
                return "$\(text)\(suffix)"
            }
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "$" + (formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00")
    }

    static func minorUnits(for code: CurrencyCode) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code.rawValue
        return max(0, formatter.maximumFractionDigits)
    }

    static func roundUp(_ value: Decimal, currencyCode: CurrencyCode) -> Decimal {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, minorUnits(for: currencyCode), .up)
        return rounded
    }

    /// macOS 14 has no native compact currency notation. Keep the currency
    /// symbol and placement locale-aware, then append the same short suffixes
    /// the pre-currency TokenStats hero used. Exact value remains in help and
    /// accessibility text.
    static func legacyCompact(
        _ value: Decimal,
        currencyCode: CurrencyCode,
        locale: Locale
    ) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M")]
        guard let (unit, suffix) = units.first(where: { abs(number) >= $0.0 }) else {
            let digits = minorUnits(for: currencyCode)
            return value.formatted(
                .currency(code: currencyCode.rawValue)
                    .precision(.fractionLength(digits))
                    .locale(locale)
            )
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode.rawValue
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = abs(number / unit) < 9.95 ? 1 : 0
        let scaled = NSNumber(value: number / unit)
        return (formatter.string(from: scaled) ?? scaled.stringValue) + suffix
    }
}
