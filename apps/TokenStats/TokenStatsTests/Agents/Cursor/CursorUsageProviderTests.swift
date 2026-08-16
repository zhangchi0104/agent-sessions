//
//  CursorUsageProviderTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

@Suite(.serialized)
struct CursorUsageProviderTests {
    private func makeProvider(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> CursorUsageProvider {
        CursorStubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CursorStubURLProtocol.self]
        return CursorUsageProvider(
            session: URLSession(configuration: config),
            accessToken: { "cursor-token" }
        )
    }

    private func ok(_ json: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (response, Data(json.utf8))
    }

    @Test func parsesOfficialModelBucketsAndBillingCycleReset() async throws {
        let resetMilliseconds = 2_000_000_000_000.0
        let provider = makeProvider { request in
            CursorStubURLProtocol.lastRequest = request
            return self.ok("""
            {
              "billingCycleStart": 1997408000000,
              "billingCycleEnd": \(Int(resetMilliseconds)),
              "planUsage": {
                "totalSpend": 900,
                "includedSpend": 365,
                "bonusSpend": 150,
                "remaining": 1635,
                "limit": 2000,
                "autoPercentUsed": 1.2166666666666666,
                "apiPercentUsed": 0,
                "totalPercentUsed": 1.0579710144927537
              },
              "enabled": true
            }
            """, for: request)
        }

        let windows = try await provider.fetchUsage().windows
        #expect(windows.count == 2)
        #expect(windows.map(\.identity) == [.cursorModels, .otherModels])
        #expect(windows.map(\.percentConsumed) == [1.2166666666666666, 0])
        #expect(windows.allSatisfy {
            $0.resetAt == Date(timeIntervalSince1970: resetMilliseconds / 1_000)
        })

        let sent = try #require(CursorStubURLProtocol.lastRequest)
        #expect(sent.httpMethod == "POST")
        #expect(requestBody(sent) == Data("{}".utf8))
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer cursor-token")
        #expect(sent.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func acceptsSnakeCaseModelBucketsAndNumericBillingCycleEnd() throws {
        let windows = try CursorUsageSnapshotParser.parse(Data("""
        {
          "billing_cycle_end": 2000000000000,
          "plan_usage": { "auto_percent_used": 12.5, "api_percent_used": 4 }
        }
        """.utf8))

        #expect(windows.map(\.identity) == [.cursorModels, .otherModels])
        #expect(windows.map(\.percentConsumed) == [12.5, 4])
    }

    @Test func rejectsAggregateSpendWhenOfficialBucketsAreMissing() {
        #expect(throws: DecodingError.self) {
            try CursorUsageSnapshotParser.parse(Data("""
            {
              "billingCycleEnd": "1787443288000",
              "planUsage": {
                "includedSpend": 365,
                "limit": 2000,
                "totalPercentUsed": 1.0579710144927537
              },
              "enabled": true
            }
            """.utf8))
        }
    }

    @Test(arguments: ["autoPercentUsed", "apiPercentUsed"])
    func rejectsAResponseMissingEitherOfficialBucket(_ onlyField: String) {
        #expect(throws: DecodingError.self) {
            try CursorUsageSnapshotParser.parse(Data("""
            {"planUsage":{"\(onlyField)":12.5}}
            """.utf8))
        }
    }

    @Test func cursorLoginUsesAnAbsoluteDeadline() async {
        CursorStubURLProtocol.lastRequest = nil
        CursorStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CursorStubURLProtocol.self]
        let client = CursorOAuthClient(
            session: URLSession(configuration: config),
            loginTimeout: .zero,
            retryDelay: .zero
        )

        do {
            _ = try await client.waitForLogin(
                pkce: PKCE(verifier: "verifier", challenge: "challenge"),
                uuid: "uuid"
            )
            Issue.record("An expired login deadline was accepted.")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected login error: \(error)")
        }
        #expect(CursorStubURLProtocol.lastRequest == nil)
    }

    @Test func cursorLoginCapsEachRequestToTheRemainingDeadline() async throws {
        CursorStubURLProtocol.lastRequest = nil
        CursorStubURLProtocol.handler = { request in
            CursorStubURLProtocol.lastRequest = request
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"accessToken":"access","refreshToken":"refresh"}"#.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CursorStubURLProtocol.self]
        let client = CursorOAuthClient(
            session: URLSession(configuration: config),
            loginTimeout: .seconds(2),
            retryDelay: .zero
        )

        _ = try await client.waitForLogin(
            pkce: PKCE(verifier: "verifier", challenge: "challenge"),
            uuid: "uuid"
        )

        let timeout = try #require(CursorStubURLProtocol.lastRequest?.timeoutInterval)
        #expect(timeout > 0)
        #expect(timeout <= 2)
    }

    @Test func rejectsDisabledOrMissingPlanUsage() async {
        let provider = makeProvider { request in
            self.ok(#"{"enabled":false,"planUsage":{"includedSpend":10,"limit":100}}"#,
                    for: request)
        }

        await #expect(throws: UsageError.self) {
            try await provider.fetchUsage()
        }
    }

    @Test func throwsBadResponseOnNon200() async {
        let provider = makeProvider { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"code":"unauthenticated"}"#.utf8))
        }

        await #expect(throws: UsageError.self) {
            try await provider.fetchUsage()
        }
    }

    private func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

final class CursorStubURLProtocol: URLProtocol {
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
