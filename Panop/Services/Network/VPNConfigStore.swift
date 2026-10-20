import Foundation

/// The WireGuard configuration the person pasted, which holds a private key. Kept in the Keychain of this
/// device only (never in UserDefaults, never in the iCloud-synced stores).
nonisolated protocol VPNConfigStore: Sendable {
    func load() -> String?
    func save(_ text: String)
    func delete()
}

nonisolated struct KeychainVPNConfigStore: VPNConfigStore {
    private let keychain = KeychainCredentialStore(service: "com.panop.vpn")
    private let account = "wireguard"

    func load() -> String? {
        guard let data = try? keychain.loadData(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ text: String) {
        try? keychain.saveData(Data(text.utf8), for: account)
    }

    func delete() {
        try? keychain.delete(for: account)
    }
}

nonisolated class InMemoryVPNConfigStore: VPNConfigStore, @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?

    init(_ text: String? = nil) {
        self.text = text
    }

    func load() -> String? {
        lock.withLock { text }
    }

    func save(_ text: String) {
        lock.withLock { self.text = text }
    }

    func delete() {
        lock.withLock { text = nil }
    }
}
