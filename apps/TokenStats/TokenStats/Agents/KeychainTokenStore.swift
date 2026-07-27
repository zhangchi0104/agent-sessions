//
//  KeychainTokenStore.swift
//  TokenStats
//
//  Thin I/O wrapper that stores TokenStats' OWN OAuth tokens in its OWN
//  keychain item — never Claude Code's (ADR-0001). One JSON-encoded generic
//  password item.
//
//  Uses the LEGACY (file-based) login keychain — deliberately NOT the
//  data-protection keychain (kSecUseDataProtectionKeychain). The data-protection
//  keychain grants access via a keychain access group, which requires the
//  `keychain-access-groups` entitlement. On a notarized, non-sandboxed
//  Developer ID app with no embedded provisioning profile, AMFI treats
//  keychain-access-groups as an unauthorized restricted entitlement and
//  SIGKILLs the process at launch ("TokenStats.app can't be opened", exit 137)
//  — codesign/spctl/notarization all pass; only the runtime kernel rejects it.
//  See ADR-0004.
//
//  The legacy keychain needs no entitlement: access is governed by the item's
//  ACL, keyed to the app's code signature. TokenStats creates and reads its own
//  item, so it adds itself to that ACL on save and never prompts on its own
//  reads. The released build has a stable Developer ID signature, so the grant
//  persists across launches. (During local development the signature changes per
//  build, so a debug rebuild may re-prompt for the login-keychain password once
//  — a dev-only annoyance, not a shipped-app issue.) AgentTokenCache also holds
//  the token in memory, so we touch the keychain at most once per launch.
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

    /// Distinguishes "no account stored" from "the keychain would not answer".
    /// A locked login keychain or a denied ACL prompt reports the latter, so the
    /// caller can retry instead of concluding the user is signed out.
    func load() -> Result<OAuthTokens?, Error> {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            // An item that won't decode is a stored account we can't use; that
            // is a genuine "nothing here", not a read failure to retry.
            guard let data = result as? Data else { return .success(nil) }
            return .success(try? JSONDecoder().decode(OAuthTokens.self, from: data))
        case errSecItemNotFound:
            return .success(nil)
        default:
            return .failure(KeychainError.status(status))
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Intentionally the legacy login keychain: the data-protection
            // keychain would require the keychain-access-groups entitlement,
            // which AMFI SIGKILLs this Developer ID app over at launch. See the
            // file header and ADR-0004.
        ]
    }

    enum KeychainError: Error { case status(OSStatus) }
}
