//
//  ExchangeRateProviderSupport.swift
//  TokenStats
//
//  Shared transport and whole-table validation for exchange-rate adapters.
//

import Foundation

nonisolated enum ExchangeRateProviderSupport {
    /// Territory and pegged-currency aliases published by the supported APIs,
    /// plus ISO codes newer than TokenStats' minimum macOS currency catalog.
    /// These rows are validated, then omitted only when Foundation cannot
    /// localize them. Any other unknown three-letter code rejects the table.
    private static let knownCodesNotGuaranteedByHostCatalog: Set<String> = [
        "FOK", "GGP", "IMP", "JEP", "KID", "TVD", "XCG", "ZWG",
    ]

    static func request(
        for source: ExchangeRateSource,
        expectedProviderID: ExchangeRateProviderID,
        accept: String
    ) throws -> URLRequest {
        guard source.providerID == expectedProviderID, source.isValid else {
            throw ExchangeRateProviderError.invalidSource(expectedProviderID)
        }
        var request = URLRequest(url: source.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    static func responseData(
        for request: URLRequest,
        providerID: ExchangeRateProviderID,
        session: URLSession
    ) async throws -> Data {
        let (data, response) = try await session.data(
            for: request,
            delegate: ExchangeRateRedirectRejectingDelegate.shared
        )
        guard let http = response as? HTTPURLResponse else {
            throw ExchangeRateProviderError.badResponse(providerID, status: -1)
        }
        guard http.statusCode == 200 else {
            throw ExchangeRateProviderError.badResponse(providerID, status: http.statusCode)
        }
        return data
    }

    static func normalizedCurrencyCode(
        _ value: String,
        providerID: ExchangeRateProviderID
    ) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.utf8.count == 3,
              normalized.utf8.allSatisfy({ $0 >= 65 && $0 <= 90 })
        else {
            throw ExchangeRateProviderError.invalidQuote(providerID, value)
        }
        return normalized
    }

    /// Returns nil only for a documented provider extension that the current
    /// host's Foundation currency catalog cannot represent.
    static func currencyCode(
        _ normalized: String,
        providerID: ExchangeRateProviderID
    ) throws -> CurrencyCode? {
        if let code = CurrencyCode(normalized) {
            return code
        }
        guard knownCodesNotGuaranteedByHostCatalog.contains(normalized) else {
            throw ExchangeRateProviderError.invalidQuote(providerID, normalized)
        }
        return nil
    }

    static func rateDate(
        _ value: String,
        providerID: ExchangeRateProviderID
    ) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value),
              formatter.string(from: date) == value
        else {
            throw ExchangeRateProviderError.invalidDate(providerID, value)
        }
        return date
    }

    static func validatedCompleteTable(
        _ quotes: [ExchangeRateQuote],
        providerID: ExchangeRateProviderID
    ) throws -> [ExchangeRateQuote] {
        guard !quotes.isEmpty else {
            throw ExchangeRateProviderError.emptyTable(providerID)
        }
        let minimum = providerID.descriptor.minimumUsableQuoteCount
        guard quotes.count >= minimum else {
            throw ExchangeRateProviderError.insufficientTable(
                providerID,
                actual: quotes.count,
                minimum: minimum
            )
        }
        return quotes.sorted { $0.quoteCode < $1.quoteCode }
    }
}

/// A configured source is the exact network destination the user approved.
/// Reject every redirect so validation and later refreshes cannot silently
/// contact a different host or downgrade away from HTTPS.
nonisolated final class ExchangeRateRedirectRejectingDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    static let shared = ExchangeRateRedirectRejectingDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
