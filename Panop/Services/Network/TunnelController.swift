import Foundation
import Observation
import PanopCore

/// Panop's own WireGuard tunnel, from the person's pasted configuration: off, connecting, up or failed.
///
/// **Fails closed.** Once the switch is on, `ProviderNetwork` holds all provider traffic from the very first
/// moment (before the tunnel is up) until the tunnel answers, and again whenever it fails. Nothing ever falls
/// back to a direct connection.
@MainActor
@Observable
final class TunnelController {
    static let shared = TunnelController()
    nonisolated static let enabledKey = "panop.vpn.tunnel.enabled"
    /// Whether the configuration travels through iCloud (when iCloud is on). Not whether the tunnel is used.
    nonisolated static let syncsKey = "panop.vpn.tunnel.syncs"
    nonisolated static let digestKey = "panop.vpn.tunnel.digest"

    enum State: Equatable {
        case off
        case connecting
        case connected
        case failed(Failure)
    }

    enum Failure: Equatable {
        case noConfiguration
        case unreachable
        case invalid(String)
    }

    private(set) var state = State.off
    private(set) var config: WireGuardConfig?
    private(set) var counters = TunnelCounters()

    @ObservationIgnored private let store: any VPNConfigStore
    @ObservationIgnored private let makeBackend: @Sendable () -> any TunnelBackend
    @ObservationIgnored private let network: ProviderNetwork
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var backend: (any TunnelBackend)?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var sync: VPNSyncStore?
    /// Whether the configuration is to travel: the person's switch, and iCloud being on. Set by the app.
    @ObservationIgnored var syncsConfig: @MainActor () -> Bool = { true }

    init(
        store: any VPNConfigStore = KeychainVPNConfigStore(),
        makeBackend: @escaping @Sendable () -> any TunnelBackend = { GoTunnelBackend() },
        network: ProviderNetwork = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.makeBackend = makeBackend
        self.network = network
        self.defaults = defaults
        config = store.load().flatMap { try? WireGuardConfig.parse($0) }
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    var hasConfiguration: Bool {
        config != nil
    }

    /// At launch: if the tunnel is on, traffic is held at once, before anything has a chance to leave.
    func launch() {
        guard isEnabled else { return }
        network.setRoute(.tunnelDown)
        state = .connecting
        Task { await connect() }
    }

    /// Checks the text, keeps it, and (if the tunnel is on) restarts on it. Throws what is wrong, by line.
    func importConfiguration(_ text: String) throws {
        let parsed = try WireGuardConfig.parse(text)
        store.save(parsed.text)
        config = parsed
        reconcile()
        if isEnabled {
            Task { await connect() }
        }
    }

    func removeConfiguration() {
        if syncsConfig() {
            sync?.setBlob(nil, removed: true)
        }
        defaults.removeObject(forKey: Self.digestKey)
        disconnect()
        defaults.set(false, forKey: Self.enabledKey)
        store.delete()
        config = nil
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            network.setRoute(.tunnelDown)
            state = .connecting
            Task { await connect() }
        } else {
            disconnect()
        }
    }

    func attach(sync: VPNSyncStore) {
        self.sync = sync
    }

    /// Brings this device's configuration and the record into line, as the person's setting says: a configuration
    /// goes to the record so other devices have it, one that arrived is taken into the Keychain (and the tunnel
    /// restarts on it if it is on), one taken out elsewhere is taken out here, and with the setting off the record is
    /// emptied. The decision is `SportsKeySync.decide`, which is not specific to that key. Safe to run any number of
    /// times.
    func reconcile() {
        guard let sync else { return }
        let record = sync.record
        let action = SportsKeySync.decide(
            local: store.load(),
            blob: record.blob,
            removed: record.removed,
            remembered: defaults.string(forKey: Self.digestKey),
            uploading: syncsConfig()
        )
        switch action {
        case .none:
            if let blob = record.blob {
                defaults.set(SportsKeySync.digest(blob), forKey: Self.digestKey)
            }
        case let .upload(blob):
            sync.setBlob(blob)
            defaults.set(SportsKeySync.digest(blob), forKey: Self.digestKey)
        case let .adopt(text):
            // Only a configuration this device can read is taken; anything else is left on the record.
            guard let parsed = try? WireGuardConfig.parse(text) else { return }
            store.save(parsed.text)
            config = parsed
            if let blob = record.blob {
                defaults.set(SportsKeySync.digest(blob), forKey: Self.digestKey)
            }
            if isEnabled {
                Task { await connect() }
            }
        case .removeLocal:
            store.delete()
            config = nil
            defaults.removeObject(forKey: Self.digestKey)
            if isEnabled {
                defaults.set(false, forKey: Self.enabledKey)
                disconnect()
            }
        case .withdraw:
            sync.setBlob(nil)
            defaults.removeObject(forKey: Self.digestKey)
        }
    }

    /// The app came back to the front: the system may have suspended the tunnel's sockets, so ask the server.
    func appBecameActive() {
        guard isEnabled, state == .connected, let backend else { return }
        Task {
            let alive = await Task.detached { (try? backend.waitReady(seconds: 3)) != nil }.value
            if !alive, isEnabled {
                await connect()
            }
        }
    }

    func refreshCounters() {
        if let backend, state == .connected {
            counters = backend.counters
        }
    }

    // MARK: -

    private func connect() async {
        guard let text = store.load() else {
            network.setRoute(.tunnelDown)
            state = .failed(.noConfiguration)
            return
        }
        attempt += 1
        let mine = attempt
        backend?.stop()
        network.setRoute(.tunnelDown)
        state = .connecting
        let fresh = makeBackend()
        backend = fresh
        // Starting resolves the server's name and waiting is a network round trip: not on the main thread.
        let result = await Task.detached { () -> Result<ProxyEndpoint, Error> in
            do {
                let endpoint = try fresh.start(config: text)
                try fresh.waitReady(seconds: 15)
                return .success(endpoint)
            } catch {
                return .failure(error)
            }
        }.value
        guard mine == attempt else {
            fresh.stop()
            return
        }
        switch result {
        case let .success(endpoint):
            network.setRoute(.tunnel(endpoint))
            state = .connected
            counters = fresh.counters
        case let .failure(error):
            fresh.stop()
            backend = nil
            let detail = error.localizedDescription
            state = .failed(detail.hasPrefix("line ") || detail.contains("needs") ? .invalid(detail) : .unreachable)
        }
    }

    private func disconnect() {
        attempt += 1
        backend?.stop()
        backend = nil
        network.setRoute(.direct)
        state = .off
        counters = TunnelCounters()
    }

    /// The address the world sees for traffic through the tunnel, for "Test connection". Asks a public
    /// service, and only when the person taps the button.
    func exitAddress() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        let response = try? await network.transport.send(HTTPRequest(url: url, timeout: 15))
        return response.flatMap { String(data: $0.body, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
