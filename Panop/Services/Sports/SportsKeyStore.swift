import Foundation

/// The person's sportapi.ai key on this device. The Keychain is where a device reads it from; iCloud only carries it
/// between devices (see `SportsKeySync`).
nonisolated protocol SportsKeyStore: Sendable {
    func load() -> String?
    func save(_ key: String)
    func delete()
}

nonisolated struct KeychainSportsKeyStore: SportsKeyStore {
    private let keychain = KeychainCredentialStore(service: "com.panop.sportapi")
    private let account = "apiKey"

    func load() -> String? {
        guard let data = try? keychain.loadData(for: account) else { return nil }
        return SportsKeySync.decode(data)
    }

    func save(_ key: String) {
        guard let data = SportsKeySync.encode(key) else { return }
        try? keychain.saveData(data, for: account)
    }

    func delete() {
        try? keychain.delete(for: account)
    }
}

nonisolated class InMemorySportsKeyStore: SportsKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(_ key: String? = nil) {
        self.key = key
    }

    func load() -> String? {
        lock.withLock { key }
    }

    func save(_ key: String) {
        lock.withLock { self.key = key }
    }

    func delete() {
        lock.withLock { key = nil }
    }
}

/// What this device remembers of the key on the record: a digest, never the key (see `SportsKeySync.decide`).
nonisolated struct SportsKeyMemory {
    private static let digestKey = "sportsKeyDigest"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var digest: String? {
        defaults.string(forKey: Self.digestKey)
    }

    func remember(_ digest: String) {
        defaults.set(digest, forKey: Self.digestKey)
    }

    func forget() {
        defaults.removeObject(forKey: Self.digestKey)
    }
}
