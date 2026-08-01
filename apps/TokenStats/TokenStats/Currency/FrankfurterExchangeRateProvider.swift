//
//  FrankfurterExchangeRateProvider.swift
//  TokenStats
//
//  Fetches one complete USD reference-rate table. The provider validates the
//  whole response before returning so a malformed row cannot poison cache.
//

import Foundation

nonisolated protocol ExchangeRateProviding {
    func fetchRates() async throws -> [ExchangeRateQuote]
}

nonisolated enum ExchangeRateProviderError: Error, Equatable, LocalizedError {
    case badResponse(status: Int)
    case emptyTable
    case invalidBase(String)
    case invalidQuote(String)
    case invalidRate(String)
    case duplicateQuote(String)
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case let .badResponse(status):
            return status < 0
                ? "Frankfurter returned an invalid response."
                : "Frankfurter returned HTTP \(status)."
        case .emptyTable:
            return "Frankfurter returned an empty exchange-rate table."
        case let .invalidBase(base):
            return "Frankfurter returned an unexpected base currency (\(base))."
        case let .invalidQuote(quote):
            return "Frankfurter returned an invalid currency code (\(quote))."
        case let .invalidRate(quote):
            return "Frankfurter returned an invalid rate for \(quote)."
        case let .duplicateQuote(quote):
            return "Frankfurter returned \(quote) more than once."
        case let .invalidDate(value):
            return "Frankfurter returned an invalid quote date (\(value))."
        }
    }
}

nonisolated struct FrankfurterExchangeRateProvider: ExchangeRateProviding {
    static let endpoint = URL(string: "https://api.frankfurter.dev/v2/rates?base=USD")!

    /// Frankfurter territory aliases plus ISO codes introduced after the app's
    /// minimum macOS currency catalog. They are safe to validate and omit when
    /// Foundation cannot localize them; every other unknown code is corruption.
    private static let knownCodesNotGuaranteedByHostCatalog: Set<String> = [
        "GGP", "IMP", "JEP", "XCG", "ZWG",
    ]

    var session: URLSession = .shared

    func fetchRates() async throws -> [ExchangeRateQuote] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExchangeRateProviderError.badResponse(status: -1)
        }
        guard http.statusCode == 200 else {
            throw ExchangeRateProviderError.badResponse(status: http.statusCode)
        }

        let rows = try JSONDecoder().decode([ResponseRow].self, from: data)
        guard !rows.isEmpty else { throw ExchangeRateProviderError.emptyTable }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.isLenient = false

        var seen = Set<String>()
        var quotes: [ExchangeRateQuote] = []
        quotes.reserveCapacity(rows.count)

        for row in rows {
            let base = row.base.uppercased()
            guard base == CurrencyCode.usd.rawValue else {
                throw ExchangeRateProviderError.invalidBase(row.base)
            }

            guard let normalizedQuote = Self.normalizedCurrencyCode(row.quote) else {
                throw ExchangeRateProviderError.invalidQuote(row.quote)
            }
            guard row.rate > 0 else {
                throw ExchangeRateProviderError.invalidRate(normalizedQuote)
            }
            guard seen.insert(normalizedQuote).inserted else {
                throw ExchangeRateProviderError.duplicateQuote(normalizedQuote)
            }
            guard let rateDate = dateFormatter.date(from: row.date),
                  dateFormatter.string(from: rateDate) == row.date
            else {
                throw ExchangeRateProviderError.invalidDate(row.date)
            }

            // The complete v2 table includes USD's canonical identity row.
            // Validate it, but do not persist it as an exchange-rate quote;
            // the display layer supplies USD directly at rate 1.
            if normalizedQuote == CurrencyCode.usd.rawValue {
                guard row.rate == 1 else {
                    throw ExchangeRateProviderError.invalidRate(normalizedQuote)
                }
                continue
            }

            // Frankfurter also publishes a small known set of provider aliases
            // and newer ISO codes which the host Foundation may not recognize.
            // Omit only those known codes; an arbitrary unknown value such as
            // ZZZ must still reject the whole response.
            guard let quoteCode = CurrencyCode(normalizedQuote) else {
                guard Self.knownCodesNotGuaranteedByHostCatalog.contains(normalizedQuote) else {
                    throw ExchangeRateProviderError.invalidQuote(row.quote)
                }
                continue
            }
            quotes.append(ExchangeRateQuote(
                quoteCode: quoteCode,
                rate: row.rate,
                rateDate: rateDate
            ))
        }

        guard !quotes.isEmpty else { throw ExchangeRateProviderError.emptyTable }
        return quotes.sorted { $0.quoteCode < $1.quoteCode }
    }

    private static func normalizedCurrencyCode(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.utf8.count == 3,
              normalized.utf8.allSatisfy({ $0 >= 65 && $0 <= 90 })
        else { return nil }
        return normalized
    }

    private struct ResponseRow: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Decimal
    }
}
