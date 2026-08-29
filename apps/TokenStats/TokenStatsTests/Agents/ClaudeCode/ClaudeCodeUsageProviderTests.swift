//
//  ClaudeCodeUsageProviderTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

@Suite(.serialized)
struct ClaudeCodeUsageProviderTests {
    @Test func non200DiagnosticsNeverRetainRawUsageBody() async {
        ClaudeUsageStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(
                #"{"type":"server_error","detail":"SENSITIVE-ACCOUNT-MARKER"}"#.utf8
            ))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClaudeUsageStubURLProtocol.self]
        let provider = ClaudeCodeUsageProvider(
            session: URLSession(configuration: configuration),
            accessToken: { "test-token" }
        )

        do {
            _ = try await provider.fetchUsage()
            Issue.record("Expected usage fetch to fail")
        } catch let error as UsageError {
            guard case .badResponse(let status, let body) = error else {
                Issue.record("Expected bad response, got \(error)")
                return
            }
            #expect(status == 503)
            #expect(body == "Claude Code usage response (server_error)")
            #expect(!body.contains("SENSITIVE-ACCOUNT-MARKER"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private final class ClaudeUsageStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

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
