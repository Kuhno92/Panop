import Foundation
import Security

/// The secret half of a playlist: everything that can be used to fetch it.
///
/// A whole M3U URL counts as secret, because providers routinely embed the
/// account's username and password in it. Only a display host ever leaves this
/// type and reaches the (eventually synced) playlist record.
nonisolated struct PlaylistSecret: Codable, Equatable, Sendable {
    /// The M3U URL, or the Xtream panel's base URL.
    var url: String?
    var username: String?
    var password: String?
    /// A guide URL the user supplied. May carry credentials too.
    var guideURL: String?
}

nonisolated protocol CredentialStore: Sendable {
    func save(_ secret: PlaylistSecret, for playlist: String) throws
    func load(for playlist: String) throws -> PlaylistSecret?
    func delete(for playlist: String) throws
}

nonisolated enum CredentialStoreError: Error, Equatable {
    /// A Keychain call failed. Carries the `OSStatus`, never the secret.
    case keychain(status: Int32)
    case corrupt
}

/// Keychain-backed storage, one generic-password item per playlist.
///
/// **Accessibility.** `AfterFirstUnlock`, because a background refresh runs
/// while the device is locked. `ThisDeviceOnly`, because the secret must not
/// ride iCloud Keychain: that does not reach tvOS, and syncing credentials
/// between devices is the CloudKit container's job (see ROADMAP M5).
///
/// **macOS.** The data-protection keychain is preferred, for parity with iOS.
/// It needs a keychain-access-groups entitlement, which a locally signed dev
/// build does not have, so it falls back to the file-based keychain when the
/// system reports the entitlement missing.
nonisolated struct KeychainCredentialStore: CredentialStore {
    private let service: String

    init(service: String = "com.panop.playlist-credentials") {
        self.service = service
    }

    func save(_ secret: PlaylistSecret, for playlist: String) throws {
        let data = try JSONEncoder().encode(secret)
        try withKeychain { dataProtection in
            let query = query(playlist, dataProtection: dataProtection)
            let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if update == errSecItemNotFound {
                var add = query
                add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                return SecItemAdd(add as CFDictionary, nil)
            }
            return update
        }
    }

    func load(for playlist: String) throws -> PlaylistSecret? {
        var found: Data?
        try withKeychain(alsoTryFallbackIfNotFound: true) { dataProtection in
            var query = query(playlist, dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess {
                found = result as? Data
            }
            return status
        }
        guard let found else { return nil }
        guard let secret = try? JSONDecoder().decode(PlaylistSecret.self, from: found) else {
            throw CredentialStoreError.corrupt
        }
        return secret
    }

    func delete(for playlist: String) throws {
        try withKeychain(alsoTryFallbackIfNotFound: true) { dataProtection in
            SecItemDelete(query(playlist, dataProtection: dataProtection) as CFDictionary)
        }
    }

    // MARK: - Internals

    private func query(_ playlist: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: playlist
        ]
        #if os(macOS)
            if dataProtection {
                query[kSecUseDataProtectionKeychain as String] = true
            }
        #endif
        return query
    }

    /// Runs `call` against the preferred keychain, then the fallback on macOS.
    ///
    /// Without the entitlement, writes report `errSecMissingEntitlement` but
    /// **reads report "item not found"**: the data-protection keychain just
    /// looks empty. So reads and deletes must fall back on not-found as well, or
    /// an item saved to the fallback keychain can never be read back.
    /// "Not found" is not an error: a load that finds nothing and a delete of
    /// nothing both succeed.
    private func withKeychain(alsoTryFallbackIfNotFound: Bool = false, _ call: (Bool) -> OSStatus) throws {
        #if os(macOS)
            let status = call(true)
            let needsFallback = status == errSecMissingEntitlement
                || (alsoTryFallbackIfNotFound && status == errSecItemNotFound)
            try check(needsFallback ? call(false) : status)
        #else
            try check(call(true))
        #endif
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status: status)
        }
    }
}

/// A dictionary-backed store for previews and tests that must not touch the
/// user's real Keychain.
nonisolated class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: PlaylistSecret] = [:]

    init() {}

    func save(_ secret: PlaylistSecret, for playlist: String) throws {
        lock.withLock { secrets[playlist] = secret }
    }

    func load(for playlist: String) throws -> PlaylistSecret? {
        lock.withLock { secrets[playlist] }
    }

    func delete(for playlist: String) throws {
        lock.withLock { secrets[playlist] = nil }
    }

    var isEmpty: Bool {
        lock.withLock { secrets.isEmpty }
    }
}
