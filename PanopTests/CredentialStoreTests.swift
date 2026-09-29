import Foundation
@testable import Panop
import Testing

/// Runs against the real Keychain, with a service name of its own so it can
/// never see or disturb the app's items, and cleans up after itself.
@Suite("Keychain credential store")
struct CredentialStoreTests {
    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "com.panop.tests.\(UUID().uuidString)")
    }

    @Test
    func `saves and loads a secret`() throws {
        let store = makeStore()
        let id = UUID().uuidString
        defer { try? store.delete(for: id) }

        let secret = PlaylistSecret(
            url: "http://panel.example:8080",
            username: "alice",
            password: "s3cret",
            guideURL: "http://g/x"
        )
        try store.save(secret, for: id)

        #expect(try store.load(for: id) == secret)
    }

    @Test
    func `saving again replaces the value`() throws {
        let store = makeStore()
        let id = UUID().uuidString
        defer { try? store.delete(for: id) }

        try store.save(PlaylistSecret(username: "a", password: "one"), for: id)
        try store.save(PlaylistSecret(username: "a", password: "two"), for: id)

        #expect(try store.load(for: id)?.password == "two")
    }

    @Test
    func `an unknown playlist loads as nil`() throws {
        #expect(try makeStore().load(for: UUID().uuidString) == nil)
    }

    @Test
    func `deleting removes it and deleting nothing is not an error`() throws {
        let store = makeStore()
        let id = UUID().uuidString
        try store.save(PlaylistSecret(password: "x"), for: id)

        try store.delete(for: id)
        try store.delete(for: id)

        #expect(try store.load(for: id) == nil)
    }

    @Test
    func `playlists do not see each other's secrets`() throws {
        let store = makeStore()
        let first = UUID().uuidString
        let second = UUID().uuidString
        defer {
            try? store.delete(for: first)
            try? store.delete(for: second)
        }

        try store.save(PlaylistSecret(password: "one"), for: first)
        try store.save(PlaylistSecret(password: "two"), for: second)

        #expect(try store.load(for: first)?.password == "one")
        #expect(try store.load(for: second)?.password == "two")
    }

    @Test
    func `the in-memory store behaves the same way`() throws {
        let store = InMemoryCredentialStore()
        try store.save(PlaylistSecret(password: "x"), for: "p")
        #expect(try store.load(for: "p")?.password == "x")
        try store.delete(for: "p")
        #expect(try store.load(for: "p") == nil)
    }
}
