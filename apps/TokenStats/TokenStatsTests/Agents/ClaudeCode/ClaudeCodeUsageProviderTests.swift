//
//  ClaudeCodeUsageProviderTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

@Suite(.serialized)
struct ClaudeCodeUsageProviderTests {
    private let previous = OAuthTokens(
        accessToken: "old-access",
        refreshToken: "old-refresh",
        expiresAt: .distantFuture
    )

    private func makeOAuthClient(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> OAuthClient {
        ClaudeUsageStubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClaudeUsageStubURLProtocol.self]
        return OAuthClient(session: URLSession(configuration: configuration))
    }

    @Test func classifiesUnauthorizedSeparatelyForRefreshRecovery() async {
        ClaudeUsageStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(
                #"{"type":"authentication_error","detail":"SENSITIVE-ACCOUNT-MARKER"}"#.utf8
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
            guard case .unauthorized(let body) = error else {
                Issue.record("Expected unauthorized, got \(error)")
                return
            }
            #expect(body == "Claude Code usage response (authentication_error)")
            #expect(!body.contains("SENSITIVE-ACCOUNT-MARKER"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

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

    @Test(arguments: [
        (#"{"error":"invalid_grant","error_description":"SENSITIVE"}"#,
         SessionReauthenticationReason.invalidGrant),
        (#"{"error":{"code":"refresh_token_expired","message":"SENSITIVE"}}"#, .expired),
        (#"{"code":"refresh_token_reused","message":"SENSITIVE"}"#, .reused),
        (#"{"error":{"error_code":"refresh_token_invalidated","message":"SENSITIVE"}}"#,
         .invalidated),
    ])
    func structuredRefreshRejectionsRequireReauthentication(
        body: String,
        reason: SessionReauthenticationReason
    ) async {
        let client = makeOAuthClient { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(body.utf8))
        }

        do {
            _ = try await client.refresh(refreshToken: previous.refreshToken)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.reauthenticationReason == reason)
            #expect(!error.diagnosticSummary.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func refresh401RequiresReauthenticationWithoutRetainingTheBody() async {
        let client = makeOAuthClient { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("not-json SENSITIVE".utf8))
        }

        do {
            _ = try await client.refresh(refreshToken: previous.refreshToken)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.reauthenticationReason == .unauthorized)
            #expect(error.code == nil)
            #expect(!error.diagnosticSummary.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func unknownRefresh400RemainsTemporarilyUnverifiable() async {
        let client = makeOAuthClient { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"code":"invalid_request","message":"SENSITIVE"}"#.utf8))
        }

        do {
            _ = try await client.refresh(refreshToken: previous.refreshToken)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.code == "invalid_request")
            #expect(error.reauthenticationReason == nil)
            #expect(!error.diagnosticSummary.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func authorizationCodeRejectionKeepsItsExistingUsageErrorSemantics() async {
        let client = makeOAuthClient { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"error":"invalid_grant","message":"SENSITIVE"}"#.utf8))
        }

        do {
            _ = try await client.exchangeCode("code", verifier: "verifier", state: "state")
            Issue.record("Expected code exchange to fail")
        } catch let error as UsageError {
            guard case .badResponse(let status, let body) = error else {
                Issue.record("Expected badResponse, got \(error)")
                return
            }
            #expect(status == 400)
            #expect(body == "OAuth request rejected (invalid_grant)")
            #expect(!body.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func authorizationCodeTransportFailureKeepsItsUnderlyingError() async {
        ClaudeUsageStubURLProtocol.handler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClaudeUsageStubURLProtocol.self]
        let client = OAuthClient(session: URLSession(configuration: configuration))

        do {
            _ = try await client.exchangeCode("code", verifier: "verifier", state: "state")
            Issue.record("Expected code exchange to fail")
        } catch let error as URLError {
            #expect(error.code == .badServerResponse)
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
