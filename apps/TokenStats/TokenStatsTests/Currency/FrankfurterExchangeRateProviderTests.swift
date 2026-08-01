//
//  FrankfurterExchangeRateProviderTests.swift
//  TokenStatsTests
//

import Foundation
import Testing
@testable import TokenStats

@Suite(.serialized)
struct FrankfurterExchangeRateProviderTests {
    private func provider(
        status: Int = 200,
        json: String
    ) -> FrankfurterExchangeRateProvider {
        CurrencyURLProtocol.handler = { request in
            CurrencyURLProtocol.lastRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CurrencyURLProtocol.self]
        return FrankfurterExchangeRateProvider(
            session: URLSession(configuration: configuration)
        )
    }

    @Test func requestsTheFixedFullUSDTableAndPreservesPerQuoteDates() async throws {
        let provider = provider(json: """
        [
          { "date": "2026-07-31", "base": "USD", "quote": "USD", "rate": 1.0 },
          { "date": "2026-07-31", "base": "USD", "quote": "CNY", "rate": 7.1876 },
          { "date": "2026-07-31", "base": "USD", "quote": "GGP", "rate": 0.74534 },
          { "date": "2026-07-31", "base": "USD", "quote": "IMP", "rate": 0.74534 },
          { "date": "2026-07-31", "base": "USD", "quote": "JEP", "rate": 0.74534 },
          { "date": "2026-08-01", "base": "USD", "quote": "JPY", "rate": 150.42 }
        ]
        """)

        let quotes = try await provider.fetchRates()

        let request = try #require(CurrencyURLProtocol.lastRequest)
        #expect(request.url == FrankfurterExchangeRateProvider.endpoint)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.timeoutInterval == 20)
        let expectedCodes = ["CNY", "GGP", "IMP", "JEP", "JPY"]
            .compactMap { CurrencyCode($0) }
            .map(\.rawValue)
            .sorted()
        #expect(quotes.map(\.quoteCode.rawValue) == expectedCodes)
        #expect(!quotes.contains { $0.quoteCode == .usd })
        #expect(quotes.first { $0.quoteCode.rawValue == "CNY" }?.rateDate
                != quotes.first { $0.quoteCode.rawValue == "JPY" }?.rateDate)
    }

    @Test func rejectsNonSuccessStatus() async {
        let provider = provider(status: 503, json: #"{"error":"unavailable"}"#)

        await #expect(throws: ExchangeRateProviderError.badResponse(status: 503)) {
            try await provider.fetchRates()
        }
    }

    @Test(arguments: [
        #"[{"date":"2026-08-01","base":"EUR","quote":"CNY","rate":7.1}]"#,
        #"[{"date":"2026-08-01","base":"USD","quote":"NOPE","rate":7.1}]"#,
        #"[{"date":"2026-08-01","base":"USD","quote":"ZZZ","rate":1.2},{"date":"2026-08-01","base":"USD","quote":"CNY","rate":7.1}]"#,
        #"[{"date":"2026-08-01","base":"USD","quote":"USD","rate":0.99},{"date":"2026-08-01","base":"USD","quote":"CNY","rate":7.1}]"#,
        #"[{"date":"2026-08-01","base":"USD","quote":"CNY","rate":0}]"#,
        #"[{"date":"bad","base":"USD","quote":"CNY","rate":7.1}]"#,
        #"[{"date":"2026-08-01","base":"USD","quote":"CNY","rate":7.1},{"date":"2026-08-01","base":"USD","quote":"CNY","rate":7.2}]"#,
        #"[{"date":"2026-08-01","base":"USD","quote":"GGP","rate":0.7},{"date":"2026-08-01","base":"USD","quote":"GGP","rate":0.8},{"date":"2026-08-01","base":"USD","quote":"CNY","rate":7.1}]"#,
    ])
    func rejectsInvalidWholeTables(json: String) async {
        let provider = provider(json: json)

        await #expect(throws: (any Error).self) {
            try await provider.fetchRates()
        }
    }

    @Test func rejectsAnEmptyTable() async {
        let provider = provider(json: "[]")

        await #expect(throws: ExchangeRateProviderError.emptyTable) {
            try await provider.fetchRates()
        }
    }
}

private final class CurrencyURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
