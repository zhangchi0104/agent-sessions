//
//  KeychainTokenStore.swift
//  TokenStats
//
//  Thin I/O wrapper that stores TokenStats' OWN OAuth tokens in its OWN
//  keychain item — never Claude Code's (ADR-0001). One JSON-encoded generic
//  password item.
//
//  Uses the data-protection keychain (kSecUseDataProtectionKeychain). Access is
//  governed by the app's keychain access group — declared via the
//  keychain-access-groups entitlement (see TokenStats.entitlements,
//  "$(AppIdentifierPrefix)dev.otakuma.TokenStats") — NOT by the legacy
//  interactive ACL. A sandboxed app's identity doesn't line up with the legacy
//  keychain's "Always Allow" model, so the legacy store re-prompts for the
//  login-keychain password on every rebuild/rerun; the data-protection keychain
//  grants access purely by entitlement match and never prompts.
//
//  Items live in the app's own access group, so they are private to TokenStats
//  and survive rebuilds. AuthSession also caches the token in memory, so we
//  touch the keychain at most once per launch.
//

import Foundation

struct KeychainTokenStore {
    private let service = "dev.otakuma.TokenStats.oauth"
    private let account: String

    /// One keychain item per account so Coding Agents' tokens never overwrite
    /// each other. Claude Code keeps the original "default" account for
    /// backward compatibility with already-stored tokens.
    init(account: String = "default") {
        self.account = account
    }

    func save(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        var query = baseQuery
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        // Available after first unlock so a background menu-bar refresh can read
        // the token without the Mac being actively unlocked.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func load() -> OAuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Opt into the modern, entitlement-governed keychain — no per-rebuild
            // "allow access to your keychain" prompts.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    enum KeychainError: Error { case status(OSStatus) }
}
