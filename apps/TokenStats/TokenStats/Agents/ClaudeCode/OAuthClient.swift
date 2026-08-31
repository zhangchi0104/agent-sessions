//
//  OAuthClient.swift
//  TokenStats
//
//  Thin I/O shell around OAuthFlow: opens the browser and POSTs token
//  requests. All pure logic lives in OAuthFlow.
//

import Foundation
import AppKit

struct OAuthClient {
    var session: URLSession = .shared

    func openAuthorizePage(pkce: PKCE, state: String) {
        NSWorkspace.shared.open(OAuthFlow.authorizeURL(pkce: pkce, state: state))
    }

    func exchangeCode(_ code: String, verifier: String, state: String) async throws -> OAuthTokens {
        try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthFlow.redirectURI,
            "client_id": OAuthFlow.clientID,
            "code_verifier": verifier,
            "state": state,
        ], requestKind: .authorizationCode)
    }

    func refresh(refreshToken: String) async throws -> OAuthTokens {
        try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthFlow.clientID,
        ], requestKind: .refresh)
    }

    private enum TokenRequestKind {
        case authorizationCode
        case refresh
    }

    private func postToken(
        _ body: [String: String],
        requestKind: TokenRequestKind
    ) async throws -> OAuthTokens {
        var request = URLRequest(url: OAuthFlow.tokenEndpoint)
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if requestKind == .refresh {
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    throw CancellationError()
                }
                if error is CancellationError { throw CancellationError() }
                throw OAuthRefreshError(
                    status: -1,
                    code: nil,
                    reauthenticationReason: nil,
                    kind: .transport
                )
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if requestKind == .refresh {
                throw OAuthErrorDiagnostics.refreshError(data, status: status)
            }
            throw UsageError.badResponse(
                status: status,
                body: OAuthErrorDiagnostics.summary(data, operation: "OAuth request rejected")
            )
        }
        do {
            return try OAuthFlow.parseTokens(data)
        } catch {
            if requestKind == .refresh {
                if error is CancellationError { throw CancellationError() }
                throw OAuthRefreshError(
                    status: http.statusCode,
                    code: nil,
                    reauthenticationReason: nil,
                    kind: .malformedResponse
                )
            }
            throw error
        }
    }
}
