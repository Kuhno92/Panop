import Foundation
import Observation
import PanopCore
import PanopSimkl

nonisolated protocol SimklTokenStore: Sendable {
    func load() -> SimklTokens?
    func save(_ tokens: SimklTokens)
    func delete()
}

/// The sign-in kept in the Keychain, apart from the playlists' secrets.
nonisolated struct KeychainSimklTokenStore: SimklTokenStore {
    private let keychain = KeychainCredentialStore(service: "com.panop.simkl")
    private let account = "tokens"

    func load() -> SimklTokens? {
        guard let data = try? keychain.loadData(for: account) else { return nil }
        return try? JSONDecoder().decode(SimklTokens.self, from: data)
    }

    func save(_ tokens: SimklTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        try? keychain.saveData(data, for: account)
    }

    func delete() {
        try? keychain.delete(for: account)
    }
}

nonisolated class InMemorySimklTokenStore: SimklTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SimklTokens?

    init(_ tokens: SimklTokens? = nil) {
        self.tokens = tokens
    }

    func load() -> SimklTokens? {
        lock.withLock { tokens }
    }

    func save(_ tokens: SimklTokens) {
        lock.withLock { self.tokens = tokens }
    }

    func delete() {
        lock.withLock { tokens = nil }
    }
}

/// Whether the person has connected their Simkl account, and the steps of connecting it.
///
/// One owner of the tokens: Simkl replaces the access token on every refresh, so two places refreshing
/// would keep cutting each other off. Everything that needs a token asks `accessToken()`.
@MainActor
@Observable
final class SimklAccount {
    enum State: Equatable {
        case signedOut
        /// A code is on screen and the person has not approved it yet.
        case waiting(SimklDeviceCode)
        case connected
        case failed(Failure)
    }

    enum Failure: Equatable {
        case codeExpired
        case unreachable
    }

    private(set) var state: State

    private let auth: SimklAuth
    private let store: any SimklTokenStore
    private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private var tokens: SimklTokens?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var refreshing: Task<SimklTokens?, Never>?

    init(
        auth: SimklAuth,
        store: any SimklTokenStore,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.auth = auth
        self.store = store
        self.sleep = sleep
        let saved = store.load()
        tokens = saved
        state = saved == nil ? .signedOut : .connected
    }

    isolated deinit {
        polling?.cancel()
    }

    var isConnected: Bool {
        state == .connected
    }

    /// Asks Simkl for a code to show, and starts waiting for the person to approve it.
    func signIn() async {
        polling?.cancel()
        do {
            let code = try await auth.requestCode()
            state = .waiting(code)
            polling = Task { [weak self] in await self?.waitForApproval(code) }
        } catch {
            state = .failed(.unreachable)
        }
    }

    func cancelSignIn() {
        polling?.cancel()
        polling = nil
        if case .waiting = state {
            state = .signedOut
        }
    }

    /// Ends the sign-in here at once and on Simkl's side after.
    func signOut() async {
        polling?.cancel()
        refreshing?.cancel()
        let old = tokens
        tokens = nil
        store.delete()
        state = .signedOut
        if let old {
            await auth.revoke(old)
        }
    }

    /// A token that works now, renewed first when it is about to end. Nil when signed out, or when the
    /// refresh was refused, which signs the person out: they have to approve again.
    func accessToken(now: Date = .now) async -> String? {
        guard let current = tokens else { return nil }
        guard current.isExpiring(at: now) else { return current.accessToken }
        if let refreshing {
            return await refreshing.value?.accessToken
        }
        let task = Task { [auth] () -> SimklTokens? in
            do {
                return try await auth.refresh(current, now: now)
            } catch SimklAuthError.signedOut {
                return nil
            } catch {
                // Offline or a server fault: the old token may still work, and the sign-in stays.
                return current
            }
        }
        refreshing = task
        let renewed = await task.value
        refreshing = nil
        guard tokens != nil else { return nil }
        if let renewed {
            tokens = renewed
            store.save(renewed)
            return renewed.accessToken
        }
        tokens = nil
        store.delete()
        state = .signedOut
        return nil
    }

    private func waitForApproval(_ code: SimklDeviceCode) async {
        var interval = code.interval
        while !Task.isCancelled {
            await sleep(.seconds(interval))
            guard !Task.isCancelled else { return }
            if Date.now >= code.expiresAt {
                state = .failed(.codeExpired)
                return
            }
            switch try? await auth.poll(code) {
            case let .granted(new)?:
                tokens = new
                store.save(new)
                state = .connected
                return
            case let .slowDown(slower)?:
                interval = slower
            case .expired?:
                state = .failed(.codeExpired)
                return
            case .pending?, nil:
                // A poll that did not get through is tried again at the next interval.
                continue
            }
        }
    }
}
