//
//  FrankfurterExchangeRateProvider.swift
//  TokenStats
//
//  Fetches and validates one complete Frankfurter USD reference-rate table.
//

import Foundation

nonisolated protocol ExchangeRateProviding {
    func fetchRates(from source: ExchangeRateSource) async throws -> [ExchangeRateQuote]
}

nonisolated enum ExchangeRateProviderError: Error, Equatable, LocalizedError {
    case invalidSource(ExchangeRateProviderID)
    case badResponse(ExchangeRateProviderID, status: Int)
    case invalidResponse(ExchangeRateProviderID)
    case emptyTable(ExchangeRateProviderID)
    case insufficientTable(ExchangeRateProviderID, actual: Int, minimum: Int)
    case invalidBase(ExchangeRateProviderID, String)
    case invalidQuote(ExchangeRateProviderID, String)
    case invalidRate(ExchangeRateProviderID, String)
    case duplicateQuote(ExchangeRateProviderID, String)
    case invalidDate(ExchangeRateProviderID, String)

    var errorDescription: String? {
        let providerID: ExchangeRateProviderID
        switch self {
        case let .invalidSource(id),
             let .badResponse(id, _),
             let .invalidResponse(id),
             let .emptyTable(id),
             let .insufficientTable(id, _, _),
             let .invalidBase(id, _),
             let .invalidQuote(id, _),
             let .invalidRate(id, _),
             let .duplicateQuote(id, _),
             let .invalidDate(id, _):
            providerID = id
        }

        let provider = providerID.descriptor.displayName
        switch self {
        case .invalidSource:
            return "\(provider) is configured with an invalid exchange-rate URL."
        case let .badResponse(_, status):
            return status < 0
                ? "\(provider) returned an invalid response."
                : "\(provider) returned HTTP \(status)."
        case .invalidResponse:
            return "\(provider) returned an unreadable exchange-rate response."
        case .emptyTable:
            return "\(provider) returned an empty exchange-rate table."
        case let .insufficientTable(_, actual, minimum):
            return "\(provider) returned only \(actual) usable rates; at least \(minimum) are required."
        case let .invalidBase(_, base):
            return "\(provider) returned an unexpected base currency (\(base))."
        case let .invalidQuote(_, quote):
            return "\(provider) returned an invalid currency code (\(quote))."
        case let .invalidRate(_, quote):
            return "\(provider) returned an invalid rate for \(quote)."
        case let .duplicateQuote(_, quote):
            return "\(provider) returned \(quote) more than once."
        case let .invalidDate(_, value):
            return "\(provider) returned an invalid quote date (\(value))."
        }
    }
}

nonisolated struct ExchangeRateProviderRouter: ExchangeRateProviding {
    var session: URLSession = .shared

    func fetchRates(from source: ExchangeRateSource) async throws -> [ExchangeRateQuote] {
        switch source.providerID {
        case .frankfurter:
            return try await FrankfurterExchangeRateProvider(session: session)
                .fetchRates(from: source)
        case .exchangeRateAPI:
            return try await ExchangeRateAPIProvider(session: session)
                .fetchRates(from: source)
        case .ecb:
            return try await ECBExchangeRateProvider(session: session)
                .fetchRates(from: source)
        }
    }
}

nonisolated struct FrankfurterExchangeRateProvider: ExchangeRateProviding {
    static let endpoint = ExchangeRateProviderID.frankfurter.descriptor.defaultEndpoint

    var session: URLSession = .shared

    func fetchRates(from source: ExchangeRateSource) async throws -> [ExchangeRateQuote] {
        let providerID = ExchangeRateProviderID.frankfurter
        let request = try ExchangeRateProviderSupport.request(
            for: source,
            expectedProviderID: providerID,
            accept: "application/json"
        )
        let data = try await ExchangeRateProviderSupport.responseData(
            for: request,
            providerID: providerID,
            session: session
        )

        let rows: [ResponseRow]
        do {
            rows = try JSONDecoder().decode([ResponseRow].self, from: data)
        } catch {
            throw ExchangeRateProviderError.invalidResponse(providerID)
        }
        guard !rows.isEmpty else {
            throw ExchangeRateProviderError.emptyTable(providerID)
        }

        var seen = Set<String>()
        var sawUSDIdentity = false
        var quotes: [ExchangeRateQuote] = []
        quotes.reserveCapacity(rows.count)

        for row in rows {
            let base = row.base.uppercased()
            guard base == CurrencyCode.usd.rawValue else {
                throw ExchangeRateProviderError.invalidBase(providerID, row.base)
            }

            let normalizedQuote = try ExchangeRateProviderSupport.normalizedCurrencyCode(
                row.quote,
                providerID: providerID
            )
            guard row.rate > 0 else {
                throw ExchangeRateProviderError.invalidRate(providerID, normalizedQuote)
            }
            guard seen.insert(normalizedQuote).inserted else {
                throw ExchangeRateProviderError.duplicateQuote(providerID, normalizedQuote)
            }
            let rateDate = try ExchangeRateProviderSupport.rateDate(
                row.date,
                providerID: providerID
            )

            // Frankfurter v2 includes USD's identity row. Validate it, but do
            // not persist it because the display layer supplies USD at rate 1.
            if normalizedQuote == CurrencyCode.usd.rawValue {
                guard row.rate == 1 else {
                    throw ExchangeRateProviderError.invalidRate(providerID, normalizedQuote)
                }
                sawUSDIdentity = true
                continue
            }

            guard let quoteCode = try ExchangeRateProviderSupport.currencyCode(
                normalizedQuote,
                providerID: providerID
            ) else { continue }
            quotes.append(ExchangeRateQuote(
                quoteCode: quoteCode,
                rate: row.rate,
                rateDate: rateDate
            ))
        }

        guard sawUSDIdentity else {
            throw ExchangeRateProviderError.invalidBase(
                providerID,
                "missing USD identity rate"
            )
        }

        return try ExchangeRateProviderSupport.validatedCompleteTable(
            quotes,
            providerID: providerID
        )
    }

    private struct ResponseRow: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Decimal
    }
}
