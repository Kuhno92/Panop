import CryptoKit
import Foundation
import Observation

/// What is kept of a PIN: never the PIN itself, and with it how many wrong tries it has had.
nonisolated struct StoredPIN: Codable, Equatable {
    var salt: Data
    var hash: Data
    var failures = 0
    var lockedUntil: Date?
}

nonisolated protocol PINStore: Sendable {
    func load() -> StoredPIN?
    func save(_ pin: StoredPIN)
    func delete()
}

/// The PIN in the device Keychain, apart from the playlists' secrets. It stays on this device:
/// iCloud Keychain does not reach Apple TV, and sync of settings waits for the CloudKit container.
nonisolated struct KeychainPINStore: PINStore {
    private let keychain = KeychainCredentialStore(service: "com.panop.parental")
    private let account = "pin"

    func load() -> StoredPIN? {
        guard let data = try? keychain.loadData(for: account) else { return nil }
        return try? JSONDecoder().decode(StoredPIN.self, from: data)
    }

    func save(_ pin: StoredPIN) {
        guard let data = try? JSONEncoder().encode(pin) else { return }
        try? keychain.saveData(data, for: account)
    }

    func delete() {
        try? keychain.delete(for: account)
    }
}

nonisolated class InMemoryPINStore: PINStore, @unchecked Sendable {
    private let lock = NSLock()
    private var pin: StoredPIN?

    init() {}

    func load() -> StoredPIN? {
        lock.withLock { pin }
    }

    func save(_ pin: StoredPIN) {
        lock.withLock { self.pin = pin }
    }

    func delete() {
        lock.withLock { pin = nil }
    }
}

/// A PIN that guards what a child should not change: turning adult content back on, and the PIN itself.
///
/// Wrong tries are counted and kept with the PIN, so quitting the app does not reset them: after
/// five in a row it locks for a minute, and every wrong try after that doubles the wait, up to a quarter
/// of an hour.
@MainActor
@Observable
final class ParentalControls {
    enum Attempt: Equatable {
        case accepted
        case wrong(triesLeft: Int)
        case locked(until: Date)
    }

    static let digits = 4 ... 6
    static let triesBeforeLock = 5
    static let firstLock: TimeInterval = 60
    static let longestLock: TimeInterval = 900

    private(set) var hasPIN: Bool
    private let store: any PINStore

    init(store: any PINStore) {
        self.store = store
        hasPIN = store.load() != nil
    }

    /// The Keychain, except under tests: touching the real item from a differently signed test host
    /// makes macOS ask for a password and hangs the run.
    static func live() -> ParentalControls {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return ParentalControls(store: testing || UITestMode.isActive ? InMemoryPINStore() : KeychainPINStore())
    }

    static func isValid(_ pin: String) -> Bool {
        digits.contains(pin.count) && pin.allSatisfy(\.isASCII) && pin.allSatisfy(\.isNumber)
    }

    /// Sets the PIN, replacing any. Callers check the old one first.
    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        guard Self.isValid(pin) else { return false }
        let salt = Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max) })
        store.save(StoredPIN(salt: salt, hash: Self.hash(pin, salt: salt)))
        hasPIN = true
        return true
    }

    func verify(_ pin: String, now: Date = .now) -> Attempt {
        guard var stored = store.load() else { return .accepted }
        if let until = stored.lockedUntil, until > now {
            return .locked(until: until)
        }
        if Self.hash(pin, salt: stored.salt) == stored.hash {
            stored.failures = 0
            stored.lockedUntil = nil
            store.save(stored)
            return .accepted
        }
        stored.failures += 1
        if stored.failures >= Self.triesBeforeLock {
            let doublings = stored.failures - Self.triesBeforeLock
            let wait = min(Self.firstLock * pow(2, Double(doublings)), Self.longestLock)
            let until = now.addingTimeInterval(wait)
            stored.lockedUntil = until
            store.save(stored)
            return .locked(until: until)
        }
        store.save(stored)
        return .wrong(triesLeft: Self.triesBeforeLock - stored.failures)
    }

    /// Removes the PIN when `current` is right.
    func removePIN(current: String, now: Date = .now) -> Attempt {
        let attempt = verify(current, now: now)
        if attempt == .accepted {
            store.delete()
            hasPIN = false
        }
        return attempt
    }

    private static func hash(_ pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }
}
