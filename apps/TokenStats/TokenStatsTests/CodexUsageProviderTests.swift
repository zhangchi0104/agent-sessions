//
//  CodexUsageProviderTests.swift
//  TokenStatsTests
//
//  Exercises CodexUsageProvider through a stubbed URLSession. Serialized
//  because the stub uses a shared protocol handler.
//

import Testing
import Foundation
@testable import TokenStats

@Suite(.serialized)
struct CodexUsageProviderTests {

    private func makeProvider(
        accountID: String? = "acct-123",
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> CodexUsageProvider {
        StubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return CodexUsageProvider(
            session: URLSession(configuration: config),
            accessToken: { "test-token" },
            accountID: { accountID }
        )
    }

    private func ok(_ json: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }

    @Test func parsesWindowsAndSendsAuthHeaders() async throws {
        let provider = makeProvider { request in
            StubURLProtocol.lastRequest = request
            return self.ok("""
            {
              "rate_limit": {
                "primary_window":   { "used_percent": 24, "reset_at": 1716800000 },
                "secondary_window": { "used_percent": 12, "reset_at": 1717300000 }
              }
            }
            """, for: request)
        }

        let windows = try await provider.fetchUsage().windows

        #expect(windows.map(\.label) == ["5-hour", "Weekly"])
        #expect(windows.map(\.percentConsumed) == [24, 12])

        let sent = try #require(StubURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(sent.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-123")
    }

    @Test func omitsAccountHeaderWhenNil() async throws {
        let provider = makeProvider(accountID: nil) { request in
            StubURLProtocol.lastRequest = request
            return self.ok("""
            { "rate_limit": { "primary_window": { "used_percent": 5, "reset_at": 1716800000 } } }
            """, for: request)
        }

        _ = try await provider.fetchUsage()

        let sent = try #require(StubURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }

    @Test func throwsBadResponseOnNon200() async {
        let provider = makeProvider { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"detail":"unauthorized"}"#.utf8))
        }

        await #expect(throws: UsageError.self) {
            try await provider.fetchUsage()
        }
    }

    @Test func throwsNoWindowsWhenRateLimitNull() async {
        let provider = makeProvider { request in
            self.ok(#"{ "plan_type": "plus", "rate_limit": null }"#, for: request)
        }

        await #expect(throws: UsageError.self) {
            try await provider.fetchUsage()
        }
    }
}

/// Minimal URLProtocol stub: returns a canned response from `handler`.
final class StubURLProtocol: URLProtocol {
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
