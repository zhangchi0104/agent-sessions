//
//  AdditionalExchangeRateProviderTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

@Suite(.serialized)
struct AdditionalExchangeRateProviderTests {
    @Test func exchangeRateRequestsRejectRedirects() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = try #require(URL(string: "https://rates.example.test/latest"))
        let destination = try #require(URL(string: "https://other.example.test/latest"))
        let task = session.dataTask(with: original)
        let response = try #require(HTTPURLResponse(
            url: original,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": destination.absoluteString]
        ))

        let redirect = await withCheckedContinuation { continuation in
            ExchangeRateRedirectRejectingDelegate.shared.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: destination)
            ) { request in
                continuation.resume(returning: request)
            }
        }

        #expect(redirect == nil)
    }

    @Test func routerRequestsAndParsesACompleteExchangeRateAPITable() async throws {
        let fixture = completeOpenTable()
        let session = stubSession(data: Data(fixture.json.utf8))
        let source = try ExchangeRateSource.validated(
            providerID: .exchangeRateAPI,
            endpointText: "https://rates.example.test/latest/USD"
        )

        let quotes = try await ExchangeRateProviderRouter(session: session)
            .fetchRates(from: source)

        let request = try #require(AdapterURLProtocol.lastRequest)
        #expect(request.url == source.endpoint)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.timeoutInterval == 20)
        #expect(quotes.map(\.quoteCode.rawValue) == fixture.expectedCodes)
        #expect(quotes.count >= ExchangeRateProviderID.exchangeRateAPI
            .descriptor.minimumUsableQuoteCount)
        #expect(!quotes.contains { $0.quoteCode == .usd })
        #expect(quotes.allSatisfy {
            $0.rateDate == Date(timeIntervalSince1970: 1_785_542_551)
        })
    }

    @Test func exchangeRateAPIRejectsHTTPAndMalformedWholeTables() async {
        let source = ExchangeRateSource(
            providerID: .exchangeRateAPI,
            endpoint: ExchangeRateAPIProvider.endpoint
        )
        let failedSession = stubSession(status: 429, data: Data())
        await #expect(throws: ExchangeRateProviderError.badResponse(
            .exchangeRateAPI,
            status: 429
        )) {
            try await ExchangeRateAPIProvider(session: failedSession)
                .fetchRates(from: source)
        }

        let invalidResponses = [
            openJSON(result: "error", rateMembers: completeOpenRateMembers()),
            openJSON(base: "EUR", rateMembers: completeOpenRateMembers()),
            openJSON(last: -1, rateMembers: completeOpenRateMembers()),
            openJSON(next: 1, rateMembers: completeOpenRateMembers()),
            openJSON(endOfLife: -1, rateMembers: completeOpenRateMembers()),
            openJSON(rateMembers: completeOpenRateMembers(usdRate: "0.99")),
            openJSON(rateMembers: completeOpenRateMembers(includeUSD: false)),
            openJSON(rateMembers: completeOpenRateMembers() + #", "USD": 1"#),
            openJSON(rateMembers: completeOpenRateMembers() + #", "ZZZ": 1.2"#),
            openJSON(rateMembers: completeOpenRateMembers() + #", "CNY": -1"#),
            openJSON(rateMembers: #""USD": 1, "CNY": 7.1"#),
        ]

        for json in invalidResponses {
            let session = stubSession(data: Data(json.utf8))
            await #expect(throws: (any Error).self) {
                try await ExchangeRateAPIProvider(session: session)
                    .fetchRates(from: source)
            }
        }
    }

    @Test func exchangeRateAPIDetectsEscapedDuplicateRateKeys() async {
        let source = ExchangeRateSource(
            providerID: .exchangeRateAPI,
            endpoint: ExchangeRateAPIProvider.endpoint
        )
        let members = completeOpenRateMembers() + #", "US\u0044": 1"#
        let session = stubSession(data: Data(openJSON(rateMembers: members).utf8))

        await #expect(throws: ExchangeRateProviderError.duplicateQuote(
            .exchangeRateAPI,
            "USD"
        )) {
            try await ExchangeRateAPIProvider(session: session)
                .fetchRates(from: source)
        }
    }

    @Test func routerRequestsVersionedECBDataAndDerivesUSDCrossRates() async throws {
        let fixture = completeECBTable()
        let session = stubSession(data: Data(fixture.csv.utf8))
        let source = try ExchangeRateSource.validated(
            providerID: .ecb,
            endpointText: "https://ecb.example.test/service/data/EXR/D..EUR.SP00.A"
        )

        let quotes = try await ExchangeRateProviderRouter(session: session)
            .fetchRates(from: source)

        let request = try #require(AdapterURLProtocol.lastRequest)
        #expect(request.url == source.endpoint)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == ECBExchangeRateProvider.accept)
        #expect(request.timeoutInterval == 20)
        #expect(quotes.count >= ExchangeRateProviderID.ecb.descriptor.minimumUsableQuoteCount)
        #expect(quotes.first { $0.quoteCode.rawValue == "JPY" }?.rate == 150)
        #expect(quotes.first { $0.quoteCode.rawValue == "EUR" }?.rate == Decimal(1) / Decimal(string: "1.2")!)
        #expect(!quotes.contains { $0.quoteCode.rawValue == fixture.staleCode })
        #expect(quotes.allSatisfy { $0.rateDate == fixture.currentDate })
    }

    @Test func ecbRejectsHTTPAndMalformedWholeTables() async {
        let source = ExchangeRateSource(
            providerID: .ecb,
            endpoint: ECBExchangeRateProvider.endpoint
        )
        let failedSession = stubSession(status: 503, data: Data())
        await #expect(throws: ExchangeRateProviderError.badResponse(.ecb, status: 503)) {
            try await ECBExchangeRateProvider(session: failedSession)
                .fetchRates(from: source)
        }

        let complete = completeECBTable().csv
        let wrongHeader = complete.replacingOccurrences(of: "Key,Frequency", with: "KEY,Frequency")
        let duplicate = complete + ecbRow(code: "USD", date: "2026-07-31", rate: "1.2") + "\n"
        let unknown = complete + ecbRow(code: "ZZZ", date: "2026-07-31", rate: "1.1") + "\n"
        let badDate = complete.replacingOccurrences(
            of: "2026-07-31,180",
            with: "bad-date,180"
        )
        let badRate = complete.replacingOccurrences(
            of: "2026-07-31,180",
            with: "2026-07-31,0"
        )
        let badDenominator = complete.replacingOccurrences(
            of: ",EUR (Euro),SP00 (Spot),",
            with: ",GBP (Pound sterling),SP00 (Spot),"
        )
        let missingUSD = complete
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("EXR.D.USD.EUR.SP00.A") }
            .joined(separator: "\n")
        let insufficient = ecbHeader + "\n"
            + ecbRow(code: "USD", date: "2026-07-31", rate: "1.2") + "\n"
            + ecbRow(code: "CNY", date: "2026-07-31", rate: "8.4") + "\n"

        for csv in [
            wrongHeader,
            duplicate,
            unknown,
            badDate,
            badRate,
            badDenominator,
            missingUSD,
            insufficient,
            ecbHeader + "\n",
        ] {
            let session = stubSession(data: Data(csv.utf8))
            await #expect(throws: (any Error).self) {
                try await ECBExchangeRateProvider(session: session)
                    .fetchRates(from: source)
            }
        }
    }

    @Test func ecbRejectsUSDAnchorOlderThanLatestObservationDate() async {
        let source = ExchangeRateSource(
            providerID: .ecb,
            endpoint: ECBExchangeRateProvider.endpoint
        )
        let mixedDateTable = completeECBTable().csv.replacingOccurrences(
            of: "2026-07-31,180",
            with: "2026-08-01,180"
        )
        let session = stubSession(data: Data(mixedDateTable.utf8))

        await #expect(throws: ExchangeRateProviderError.invalidBase(
            .ecb,
            "USD/EUR cross-rate is not from the latest observation date"
        )) {
            try await ECBExchangeRateProvider(session: session)
                .fetchRates(from: source)
        }
    }

    private func stubSession(status: Int = 200, data: Data) -> URLSession {
        AdapterURLProtocol.handler = { request in
            AdapterURLProtocol.lastRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AdapterURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func completeOpenTable() -> (json: String, expectedCodes: [String]) {
        let codes = supportedCodes(
            prioritizing: ["CNY", "JPY"],
            count: ExchangeRateProviderID.exchangeRateAPI.descriptor.minimumUsableQuoteCount
        )
        return (
            openJSON(rateMembers: completeOpenRateMembers(codes: codes)),
            codes.sorted()
        )
    }

    private func completeOpenRateMembers(
        codes: [String]? = nil,
        includeUSD: Bool = true,
        usdRate: String = "1"
    ) -> String {
        let selectedCodes = codes ?? supportedCodes(
            prioritizing: ["CNY", "JPY"],
            count: ExchangeRateProviderID.exchangeRateAPI.descriptor.minimumUsableQuoteCount
        )
        var members: [String] = includeUSD ? [#""USD": \#(usdRate)"#] : []
        members += selectedCodes.enumerated().map { index, code in
            #""\#(code)": \#(index + 2)"#
        }
        return members.joined(separator: ", ")
    }

    private func openJSON(
        result: String = "success",
        last: Int64 = 1_785_542_551,
        next: Int64 = 1_785_629_821,
        endOfLife: Int64 = 0,
        base: String = "USD",
        rateMembers: String
    ) -> String {
        """
        {
          "result": "\(result)",
          "time_last_update_unix": \(last),
          "time_next_update_unix": \(next),
          "time_eol_unix": \(endOfLife),
          "base_code": "\(base)",
          "rates": { \(rateMembers) }
        }
        """
    }

    private var ecbHeader: String {
        "Key,Frequency,Currency,Currency denominator,Exchange rate type,"
            + "Series variation - EXR context,Time period or range,Observation value"
    }

    private func completeECBTable() -> (csv: String, currentDate: Date, staleCode: String) {
        let minimum = ExchangeRateProviderID.ecb.descriptor.minimumUsableQuoteCount
        let codes = supportedCodes(
            prioritizing: ["JPY", "CNY"],
            excluding: ["EUR", "USD", "ARS"],
            count: minimum - 1
        )
        var rows = [ecbRow(code: "USD", date: "2026-07-31", rate: "1.2")]
        rows += codes.enumerated().map { index, code in
            let rate = code == "JPY" ? "180" : String(index + 2)
            return ecbRow(code: code, date: "2026-07-31", rate: rate)
        }
        rows.append(ecbRow(code: "FOK", date: "2026-07-31", rate: "8"))
        rows.append(ecbRow(code: "ARS", date: "2020-10-30", rate: "91.5953"))
        return (
            ([ecbHeader] + rows).joined(separator: "\r\n") + "\r\n",
            utcDate("2026-07-31"),
            "ARS"
        )
    }

    private func ecbRow(code: String, date: String, rate: String) -> String {
        "EXR.D.\(code).EUR.SP00.A,D (Daily),\(code) (Test currency),EUR (Euro),"
            + "SP00 (Spot),A (Average),\(date),\(rate)"
    }

    private func supportedCodes(
        prioritizing preferred: [String],
        excluding excluded: Set<String> = [],
        count: Int
    ) -> [String] {
        var result = preferred.filter {
            CurrencyCode($0) != nil && $0 != "USD" && !excluded.contains($0)
        }
        let extras = Locale.Currency.isoCurrencies
            .map(\.identifier)
            .filter {
                $0 != "USD" && !excluded.contains($0)
                    && !result.contains($0) && CurrencyCode($0) != nil
            }
            .sorted()
        result.append(contentsOf: extras.prefix(max(0, count - result.count)))
        return Array(result.prefix(count))
    }

    private func utcDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }
}

private final class AdapterURLProtocol: URLProtocol {
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
