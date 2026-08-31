//
//  CodexOAuthClientTests.swift
//  TokenStatsTests
//

import Foundation
import Testing

@Suite(.serialized)
struct CodexOAuthClientTests {
    private let previous = OAuthTokens(
        accessToken: "old-access",
        refreshToken: "old-refresh",
        expiresAt: .distantPast,
        accountID: "acct-123"
    )

    private func makeClient(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> CodexOAuthClient {
        CodexOAuthClientStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexOAuthClientStub.self]
        return CodexOAuthClient(session: URLSession(configuration: configuration))
    }

    private func response(_ request: URLRequest, status: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(body.utf8))
    }

    @Test func refreshUsesTheExactJSONContractAndCarriesForwardOmittedFields() async throws {
        let client = makeClient { request in
            CodexOAuthClientStub.lastRequest = request
            return self.response(
                request,
                status: 200,
                body: #"{"access_token":"new-access","expires_in":3600}"#
            )
        }

        let refreshed = try await client.refresh(tokens: previous)

        #expect(refreshed.accessToken == "new-access")
        #expect(refreshed.refreshToken == "old-refresh")
        #expect(refreshed.accountID == "acct-123")
        let request = try #require(CodexOAuthClientStub.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(requestBody(request))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == [
            "client_id": CodexOAuthFlow.clientID,
            "grant_type": "refresh_token",
            "refresh_token": "old-refresh",
        ])
    }

    @Test func refreshAdoptsRotatedPairWithoutExpiresInAndUsesAccessJWTExpiry() async throws {
        let expectedExpiry = Date(timeIntervalSince1970: 2_000_000_000)
        let access = jwt(payload: ["exp": expectedExpiry.timeIntervalSince1970])
        let client = makeClient { request in
            self.response(
                request,
                status: 200,
                body: #"{"access_token":"\#(access)","refresh_token":"rotated-refresh"}"#
            )
        }

        let refreshed = try await client.refresh(tokens: previous)

        #expect(refreshed.accessToken == access)
        #expect(refreshed.refreshToken == "rotated-refresh")
        #expect(refreshed.expiresAt == expectedExpiry)
        #expect(refreshed.accountID == previous.accountID)
    }

    @Test func refreshOnlyResponseCarriesForwardAccessExpiryAndAccount() async throws {
        let client = makeClient { request in
            self.response(
                request,
                status: 200,
                body: #"{"refresh_token":"rotated-refresh"}"#
            )
        }

        let refreshed = try await client.refresh(tokens: previous)

        #expect(refreshed.accessToken == previous.accessToken)
        #expect(refreshed.refreshToken == "rotated-refresh")
        #expect(refreshed.expiresAt == previous.expiresAt)
        #expect(refreshed.accountID == previous.accountID)
    }

    @Test func emptySuccessfulRefreshResponseIsTransientAndSanitized() async {
        let client = makeClient { request in
            self.response(request, status: 200, body: #"{"secret":"SENSITIVE"}"#)
        }

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.kind == .malformedResponse)
            #expect(error.reauthenticationReason == nil)
            #expect(!error.diagnosticSummary.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func expiresInWithoutAnyRotatedTokenIsRejected() async {
        let client = makeClient { request in
            self.response(request, status: 200, body: #"{"expires_in":3600}"#)
        }

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.kind == .malformedResponse)
            #expect(error.reauthenticationReason == nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: [0, -1])
    func nonPositiveExpiresInIsTransientAndMalformed(expiresIn: Int) async {
        let client = makeClient { request in
            self.response(
                request,
                status: 200,
                body: #"{"access_token":"expired-access","expires_in":\#(expiresIn)}"#
            )
        }

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.kind == .malformedResponse)
            #expect(error.reauthenticationReason == nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func refreshTransportFailureIsTransientAndSanitized() async {
        CodexOAuthClientStub.handler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexOAuthClientStub.self]
        let client = CodexOAuthClient(session: URLSession(configuration: configuration))

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.kind == .transport)
            #expect(error.reauthenticationReason == nil)
            #expect(error.diagnosticSummary == "OAuth refresh request unavailable")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func authorizationCodeExchangeRemainsFormURLEncoded() async throws {
        let client = makeClient { request in
            CodexOAuthClientStub.lastRequest = request
            return self.response(
                request,
                status: 200,
                body: #"{"access_token":"access","refresh_token":"refresh","expires_in":3600}"#
            )
        }

        let code = "code +/中文"
        let verifier = "verifier+/="
        let redirectURI = "http://localhost/cb?x=1&y=2"
        _ = try await client.exchangeCode(
            code,
            verifier: verifier,
            redirectURI: redirectURI
        )

        let request = try #require(CodexOAuthClientStub.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = try #require(requestBody(request))
        let text = try #require(String(data: body, encoding: .utf8))
        let items = try #require(URLComponents(string: "?\(text)")?.queryItems)
        let fields = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(fields == [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": CodexOAuthFlow.clientID,
            "code_verifier": verifier,
        ])
    }

    @Test(arguments: [
        (#"{"error":"invalid_grant","error_description":"SENSITIVE"}"#, SessionReauthenticationReason.invalidGrant),
        (#"{"error":{"code":"refresh_token_expired","message":"SENSITIVE"}}"#, .expired),
        (#"{"error":{"message":"refresh_token_expired","detail":"SENSITIVE"}}"#, .expired),
        (#"{"code":"refresh_token_reused","message":"SENSITIVE"}"#, .reused),
        (#"{"error_code":"refresh_token_invalidated","message":"SENSITIVE"}"#, .invalidated),
        (#"{"error":{"error_code":"refresh_token_invalidated","message":"SENSITIVE"}}"#, .invalidated),
    ])
    func exactStructuredRefreshCodesRequireReauthentication(
        body: String,
        reason: SessionReauthenticationReason
    ) async {
        let client = makeClient { request in
            self.response(request, status: 400, body: body)
        }

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.reauthenticationReason == reason)
            #expect(!error.diagnosticSummary.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func refresh401RequiresReauthenticationWithoutAnErrorBody() async {
        let client = makeClient { request in
            self.response(request, status: 401, body: "not-json SENSITIVE")
        }

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.reauthenticationReason == .unauthorized)
            #expect(error.code == nil)
            #expect(!error.diagnosticSummary.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func aGenericTopLevelCodeDoesNotHideANestedTerminalCode() async {
        let client = makeClient { request in
            self.response(
                request,
                status: 400,
                body: #"{"error":"invalid_request","details":{"code":"invalid_grant","message":"SENSITIVE"}}"#
            )
        }

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.code == "invalid_grant")
            #expect(error.reauthenticationReason == .invalidGrant)
            #expect(!error.diagnosticSummary.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func descriptiveTextAloneNeverClassifiesATerminalSession() async {
        let client = makeClient { request in
            self.response(
                request,
                status: 503,
                body: #"{"code":"server_error","message":"refresh token expired and reused"}"#
            )
        }

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.code == "server_error")
            #expect(error.reauthenticationReason == nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func unsafeStructuredCodeIsOmittedFromDiagnostics() async {
        let client = makeClient { request in
            self.response(
                request,
                status: 503,
                body: #"{"code":"server_error\nSENSITIVE","message":"SENSITIVE"}"#
            )
        }

        do {
            _ = try await client.refresh(tokens: previous)
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            #expect(error.code == nil)
            #expect(error.reauthenticationReason == nil)
            #expect(!error.diagnosticSummary.contains("SENSITIVE"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func sharedOAuthDiagnosticsNeverIncludeRawAuthenticationContent() {
        let summary = OAuthErrorDiagnostics.summary(
            Data(#"{"error":{"code":"invalid_request","message":"SENSITIVE-BEARER"}}"#.utf8),
            operation: "OAuth request failed"
        )

        #expect(summary == "OAuth request failed (invalid_request)")
        #expect(!summary.contains("SENSITIVE-BEARER"))
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

    private func jwt(payload: [String: Any]) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncodedString()
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(header).\(payloadData.base64URLEncodedString()).signature"
    }
}

private final class CodexOAuthClientStub: URLProtocol {
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
