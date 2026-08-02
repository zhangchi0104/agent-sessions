//
//  CodexOAuthFlowTests.swift
//  TokenStatsTests
//
//  Pure OAuth helpers for Codex: authorize-URL construction, token-response
//  parsing, id_token account-id extraction, and loopback callback parsing.
//

import Testing
import Foundation
@testable import TokenStats

struct CodexOAuthFlowTests {

    private func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    @Test func authorizeURLCarriesLoopbackRedirectAndPKCE() throws {
        let pkce = PKCE(verifier: "verifier", challenge: "challenge")
        let url = CodexOAuthFlow.authorizeURL(
            pkce: pkce, state: "state-123",
            redirectURI: CodexOAuthFlow.redirectURI(port: 1455)
        )
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(url.absoluteString.hasPrefix("https://auth.openai.com/oauth/authorize"))
        #expect(value("client_id") == CodexOAuthFlow.clientID)
        #expect(value("redirect_uri") == "http://localhost:1455/auth/callback")
        #expect(value("response_type") == "code")
        #expect(value("code_challenge") == "challenge")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("state") == "state-123")
        #expect(value("codex_cli_simplified_flow") == "true")
        #expect(value("scope") == CodexOAuthFlow.scopes)
    }

    @Test func parsesTokensAndExtractsAccountIDFromIDToken() throws {
        // A JWT whose payload nests chatgpt_account_id under the OpenAI auth claim.
        let payload = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-xyz"}}"#
        let idToken = "header.\(base64URL(payload)).signature"
        let json = Data("""
        {
          "access_token": "at",
          "refresh_token": "rt",
          "expires_in": 3600,
          "id_token": "\(idToken)"
        }
        """.utf8)

        let now = Date(timeIntervalSince1970: 1_000_000)
        let tokens = try CodexOAuthFlow.parseTokens(json, now: now)

        #expect(tokens.accessToken == "at")
        #expect(tokens.refreshToken == "rt")
        #expect(tokens.expiresAt == now.addingTimeInterval(3600))
        #expect(tokens.accountID == "acct-xyz")
    }

    @Test func tolueratesRefreshResponseWithoutRefreshOrIDToken() throws {
        let json = Data(#"{ "access_token": "at2", "expires_in": 3600 }"#.utf8)

        let tokens = try CodexOAuthFlow.parseTokens(json)

        #expect(tokens.accessToken == "at2")
        #expect(tokens.refreshToken == "")
        #expect(tokens.accountID == nil)
    }

    @Test func accountIDIsNilWhenIDTokenLacksClaim() {
        let idToken = "header.\(base64URL(#"{"sub":"user"}"#)).sig"
        #expect(CodexOAuthFlow.accountID(fromIDToken: idToken) == nil)
        #expect(CodexOAuthFlow.accountID(fromIDToken: "not-a-jwt") == nil)
    }

    @Test func parsesLoopbackCallbackFromRequestLine() {
        let request = "GET /auth/callback?code=abc123&state=state-123 HTTP/1.1\r\nHost: localhost:1455\r\n\r\n"
        let callback = LoopbackAuthListener.parseCallback(httpRequest: request)

        #expect(callback == LoopbackAuthListener.Callback(code: "abc123", state: "state-123"))
    }

    @Test func loopbackCallbackParsingRejectsMissingCode() {
        let request = "GET /auth/callback?state=only-state HTTP/1.1\r\n\r\n"
        #expect(LoopbackAuthListener.parseCallback(httpRequest: request) == nil)
        #expect(LoopbackAuthListener.parseCallback(httpRequest: "garbage") == nil)
    }

    @Test func loopbackCallbackHTMLDeclaresLanguageAndLocalizesCompleteCopy() {
        let fixtures: [(String, Bool, String, String, String)] = [
            (
                "en-US",
                true,
                "en",
                "Signed in to Codex",
                "You can close this tab and return to TokenStats."
            ),
            (
                "en-US",
                false,
                "en",
                "Sign-in failed",
                "No authorization code was found. Return to TokenStats and try again."
            ),
            (
                "zh-Hans-CN",
                true,
                "zh-Hans",
                "已登录 Codex",
                "你可以关闭此标签页并返回 TokenStats。"
            ),
            (
                "zh-Hans-CN",
                false,
                "zh-Hans",
                "登录失败",
                "未找到授权码。请返回 TokenStats 后重试。"
            ),
            (
                "de-DE",
                true,
                "de",
                "Bei Codex angemeldet",
                "Sie können diesen Tab schließen und zu TokenStats zurückkehren."
            ),
            (
                "de-DE",
                false,
                "de",
                "Anmeldung fehlgeschlagen",
                "Es wurde kein Autorisierungscode gefunden. Kehren Sie zu TokenStats zurück und versuchen Sie es erneut."
            ),
            (
                "fr-FR",
                true,
                "fr",
                "Connecté à Codex",
                "Vous pouvez fermer cet onglet et revenir à TokenStats."
            ),
            (
                "fr-FR",
                false,
                "fr",
                "Échec de la connexion",
                "Aucun code d’autorisation n’a été trouvé. Revenez à TokenStats et réessayez."
            ),
            (
                "ja-JP",
                true,
                "ja",
                "Codex にサインインしました",
                "このタブを閉じて TokenStats に戻ることができます。"
            ),
            (
                "ja-JP",
                false,
                "ja",
                "サインインに失敗しました",
                "認可コードが見つかりませんでした。TokenStats に戻って、もう一度お試しください。"
            ),
            (
                "ru-RU",
                true,
                "ru",
                "Вход в Codex выполнен",
                "Можно закрыть эту вкладку и вернуться в TokenStats."
            ),
            (
                "ru-RU",
                false,
                "ru",
                "Ошибка входа",
                "Код авторизации не найден. Вернитесь в TokenStats и попробуйте ещё раз."
            ),
        ]

        for (localeIdentifier, succeeded, language, heading, body) in fixtures {
            let html = LoopbackAuthListener.callbackHTML(
                succeeded: succeeded,
                localizer: AppLocalizer(locale: Locale(identifier: localeIdentifier))
            )

            #expect(html.contains(#"<html lang="\#(language)">"#))
            #expect(html.contains("<title>TokenStats</title>"))
            #expect(html.contains("<h2>\(heading)</h2>"))
            #expect(html.contains("<p>\(body)</p>"))
            #expect(html.contains("account.sign_in.callback") == false)
        }
    }
}
