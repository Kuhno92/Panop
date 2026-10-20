import Foundation
import PanopCore
import PanopTunnel

/// The running tunnel as the controller sees it. A protocol so the controller's rules can be tested without
/// a network, and so the Go framework is touched in one file.
nonisolated protocol TunnelBackend: Sendable {
    /// Brings the tunnel up from configuration text and returns where its proxies listen.
    func start(config: String) throws -> ProxyEndpoint
    /// Returns once a query through the tunnel is answered; throws when it is not within the time.
    func waitReady(seconds: Int) throws
    func stop()
    /// What went through, and when the server last answered the handshake.
    var counters: TunnelCounters { get }
}

nonisolated struct TunnelCounters: Sendable, Equatable {
    var received: Int64 = 0
    var sent: Int64 = 0
    var lastHandshake: Date?
}

nonisolated struct TunnelFailure: Error, LocalizedError {
    let reason: String
    var errorDescription: String? {
        reason
    }
}

/// wireguard-go in this process (`Packages/PanopTunnel`). Its errors name a line and never a value, so
/// their text is safe to show.
nonisolated class GoTunnelBackend: TunnelBackend, @unchecked Sendable {
    private let tunnel = TunnelNewTunnel()

    func start(config: String) throws -> ProxyEndpoint {
        guard let tunnel else { throw TunnelFailure(reason: "The tunnel could not be created.") }
        try tunnel.start(config)
        return ProxyEndpoint(
            socksPort: tunnel.socksPort(), httpPort: tunnel.httpPort(),
            username: tunnel.username(), password: tunnel.password()
        )
    }

    func waitReady(seconds: Int) throws {
        guard let tunnel else { throw TunnelFailure(reason: "The tunnel could not be created.") }
        try tunnel.waitReady(seconds)
    }

    func stop() {
        tunnel?.stop()
    }

    var counters: TunnelCounters {
        guard let tunnel else { return TunnelCounters() }
        let handshake = tunnel.lastHandshakeUnix()
        return TunnelCounters(
            received: tunnel.rxBytes(), sent: tunnel.txBytes(),
            lastHandshake: handshake > 0 ? Date(timeIntervalSince1970: TimeInterval(handshake)) : nil
        )
    }
}
