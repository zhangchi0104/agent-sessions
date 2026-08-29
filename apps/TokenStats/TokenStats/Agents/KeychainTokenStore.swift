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

import CryptoKit
import Darwin
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

    /// Stable, non-secret identity used only to select the account's lock file.
    /// It reveals neither access nor refresh token material.
    var refreshCoordinationID: String {
        Self.refreshCoordinationID(service: service, account: account)
    }

    func save(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        // Available after first unlock so a background menu-bar refresh can read
        // the token without the Mac being actively unlocked.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(addStatus)
            }
        default:
            // Never delete the previous item before a replacement is durable.
            // A failed update therefore leaves the last usable credential in
            // place instead of turning a transient Keychain error into logout.
            throw KeychainError.status(updateStatus)
        }
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

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    /// Acquire the account-scoped lock away from MainActor. The lease spans the
    /// refresh request and the following Keychain write, so a replacement app
    /// instance can wait without freezing either process's UI thread.
    func acquireRefreshCoordination() async throws -> any RefreshCoordinationLease {
        let url = Self.refreshCoordinationURL(id: refreshCoordinationID)
        do {
            return try await Task.detached(priority: .userInitiated) {
                try KeychainRefreshCoordinationLease.acquire(at: url)
            }.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Paths and POSIX details are deliberately not carried across the
            // auth/UI boundary.
            throw CredentialStoreUnavailableError()
        }
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

    private static func refreshCoordinationID(service: String, account: String) -> String {
        SHA256.hash(data: Data("\(service)\u{0}\(account)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func refreshCoordinationURL(id: String) -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("dev.otakuma.TokenStats", isDirectory: true)
            .appendingPathComponent("oauth-refresh-locks", isDirectory: true)
            .appendingPathComponent("\(id).lock", isDirectory: false)
    }

    enum KeychainError: Error { case status(OSStatus) }
}

/// A stable, owner-only file lock used solely for coordination. The filename is
/// a hash of the public Keychain service/account identity; no credential bytes
/// are written to disk or included in errors.
nonisolated private final class KeychainRefreshCoordinationLease:
    RefreshCoordinationLease,
    @unchecked Sendable {
    private let descriptor: Int32
    private let stateLock = NSLock()
    private var released = false

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(at url: URL) throws -> KeychainRefreshCoordinationLease {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw CredentialStoreUnavailableError()
        }

        var directoryStatus = stat()
        guard lstat(directory.path, &directoryStatus) == 0,
              (directoryStatus.st_mode & S_IFMT) == S_IFDIR,
              directoryStatus.st_uid == geteuid(),
              chmod(directory.path, S_IRWXU) == 0 else {
            throw CredentialStoreUnavailableError()
        }

        let descriptor = Darwin.open(
            url.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard descriptor >= 0 else { throw CredentialStoreUnavailableError() }

        var descriptorStatus = stat()
        guard fstat(descriptor, &descriptorStatus) == 0,
              (descriptorStatus.st_mode & S_IFMT) == S_IFREG,
              descriptorStatus.st_uid == geteuid(),
              fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            Darwin.close(descriptor)
            throw CredentialStoreUnavailableError()
        }

        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                Darwin.close(descriptor)
                throw CredentialStoreUnavailableError()
            }
        }

        // Lock files are never removed. Verify the path still names the inode we
        // locked so a replaced entry cannot split coordination across two files.
        var pathStatus = stat()
        guard lstat(url.path, &pathStatus) == 0,
              pathStatus.st_dev == descriptorStatus.st_dev,
              pathStatus.st_ino == descriptorStatus.st_ino else {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
            throw CredentialStoreUnavailableError()
        }
        return KeychainRefreshCoordinationLease(descriptor: descriptor)
    }

    func release() {
        stateLock.lock()
        guard !released else {
            stateLock.unlock()
            return
        }
        released = true
        stateLock.unlock()
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }

    deinit {
        release()
    }
}
