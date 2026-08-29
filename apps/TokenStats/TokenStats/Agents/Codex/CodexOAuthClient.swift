//
//  CodexOAuthClient.swift
//  TokenStats
//
//  Thin I/O shell around CodexOAuthFlow: opens the browser and POSTs token
//  requests to auth.openai.com. Code exchange is form-urlencoded; refresh uses
//  the JSON contract expected by the current Codex auth service. All pure OAuth
//  parameter logic lives in CodexOAuthFlow.
//

import Foundation
import AppKit

/// A refresh-token request failed. `reauthenticationReason` is non-nil only
/// when the response is definitive evidence that this stored session cannot be
/// refreshed. The raw auth response body is deliberately never retained.
nonisolated struct OAuthRefreshError: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case http
        case transport
        case malformedResponse
    }

    let status: Int
    let code: String?
    let reauthenticationReason: SessionReauthenticationReason?
    let kind: Kind

    init(
        status: Int,
        code: String?,
        reauthenticationReason: SessionReauthenticationReason?,
        kind: Kind = .http
    ) {
        self.status = status
        self.code = code
        self.reauthenticationReason = reauthenticationReason
        self.kind = kind
    }

    var diagnosticSummary: String {
        switch kind {
        case .http:
            if let code { return "OAuth refresh rejected (\(code))" }
            return "OAuth refresh rejected"
        case .transport:
            return "OAuth refresh request unavailable"
        case .malformedResponse:
            return "OAuth refresh response was invalid"
        }
    }
}

struct CodexOAuthClient {
    var session: URLSession = .shared

    func openAuthorizePage(pkce: PKCE, state: String, redirectURI: String) {
        NSWorkspace.shared.open(
            CodexOAuthFlow.authorizeURL(pkce: pkce, state: state, redirectURI: redirectURI)
        )
    }

    func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> OAuthTokens {
        let response = try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": CodexOAuthFlow.clientID,
            "code_verifier": verifier,
        ], requestKind: .authorizationCode)
        return try CodexOAuthFlow.parseTokens(response.data)
    }

    /// Refresh rotates the token; carry forward the prior refresh token and
    /// account id when the response omits them.
    func refresh(tokens previous: OAuthTokens) async throws -> OAuthTokens {
        let response = try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": previous.refreshToken,
            "client_id": CodexOAuthFlow.clientID,
        ], requestKind: .refresh)
        do {
            return try CodexOAuthFlow.parseRefreshTokens(
                response.data,
                previous: previous
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OAuthRefreshError(
                status: response.status,
                code: nil,
                reauthenticationReason: nil,
                kind: .malformedResponse
            )
        }
    }

    private enum TokenRequestKind: Equatable {
        case authorizationCode
        case refresh
    }

    private struct OAuthErrorMetadata {
        let codes: [String]

        var firstCode: String? { codes.first }
    }

    private struct TokenResponse {
        let status: Int
        let data: Data
    }

    private func postToken(
        _ body: [String: String],
        requestKind: TokenRequestKind
    ) async throws -> TokenResponse {
        var request = URLRequest(url: CodexOAuthFlow.tokenEndpoint)
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        switch requestKind {
        case .authorizationCode:
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(formURLEncoded(body).utf8)
        case .refresh:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if requestKind == .refresh {
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
            let metadata = oauthErrorMetadata(data)
            if requestKind == .refresh {
                let classification = refreshInvalidationClassification(
                    status: status,
                    metadata: metadata
                )
                throw OAuthRefreshError(
                    status: status,
                    code: classification.code,
                    reauthenticationReason: classification.reason
                )
            }
            // Authorization-code failures are login failures, not evidence
            // about an existing stored session. Keep only a sanitized code.
            let summary = metadata.firstCode.map { "OAuth token exchange rejected (\($0))" }
                ?? "OAuth token exchange rejected"
            throw UsageError.badResponse(status: status, body: summary)
        }
        return TokenResponse(status: http.statusCode, data: data)
    }

    private func oauthErrorMetadata(_ data: Data) -> OAuthErrorMetadata {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return OAuthErrorMetadata(codes: [])
        }

        var collected: [String] = []
        collectOAuthCodes(from: root, depth: 0, into: &collected)
        var seen = Set<String>()
        return OAuthErrorMetadata(codes: collected.filter { seen.insert($0).inserted })
    }

    private func collectOAuthCodes(
        from value: Any,
        depth: Int,
        into collected: inout [String]
    ) {
        guard depth <= 6 else { return }
        if let object = value as? [String: Any] {
            for (key, child) in object {
                if let raw = child as? String,
                   let code = normalizedOAuthCode(raw),
                   ["error", "code", "error_code", "type"].contains(key)
                    || (key == "message" && terminalReason(for: code) != nil) {
                    collected.append(code)
                }
                if child is [String: Any] || child is [Any] {
                    collectOAuthCodes(from: child, depth: depth + 1, into: &collected)
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectOAuthCodes(from: child, depth: depth + 1, into: &collected)
            }
        }
    }

    private func normalizedOAuthCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized.count <= 80 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._")
        guard normalized.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return normalized
    }

    private func refreshInvalidationClassification(
        status: Int,
        metadata: OAuthErrorMetadata
    ) -> (reason: SessionReauthenticationReason?, code: String?) {
        for code in metadata.codes {
            if let reason = terminalReason(for: code) { return (reason, code) }
        }
        if status == 401 { return (.unauthorized, metadata.firstCode) }
        return (nil, metadata.firstCode)
    }

    private func terminalReason(
        for code: String
    ) -> SessionReauthenticationReason? {
        switch code {
        case "invalid_grant": return .invalidGrant
        case "refresh_token_expired": return .expired
        case "refresh_token_reused": return .reused
        case "refresh_token_invalidated": return .invalidated
        default: return nil
        }
    }

    private func formURLEncoded(_ body: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return body
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
