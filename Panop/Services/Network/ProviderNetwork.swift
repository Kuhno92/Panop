import Foundation
import Network
import PanopCore

/// The one door for traffic to the person's providers (playlists, guides, artwork, Simkl, stream pages).
///
/// Every such request is made through here, so a rule about the network (a VPN is required, the app's own
/// tunnel is the only way out) is applied in one place and cannot be missed by a screen added later. A
/// SwiftLint rule bans `URLSession` and `URLSessionTransport` outside this folder for that reason.
nonisolated class ProviderNetwork: @unchecked Sendable {
    static let shared = ProviderNetwork()

    /// How provider traffic leaves the device.
    enum Route: Equatable {
        /// Straight out, as the system routes it (which may be through a system VPN).
        case direct
        /// The app's tunnel is switched on and not up: nothing goes, and nothing falls back to direct.
        case tunnelDown
        /// Through the app's tunnel, via its loopback proxy.
        case tunnel(ProxyEndpoint)
    }

    private let lock = NSLock()
    private var route = Route.direct
    private var systemBlock: NetworkBlock?
    private var cached: (route: Route, sessions: Sessions)?

    private struct Sessions {
        let standard: URLSession
        let images: URLSession
    }

    /// What currently holds traffic back, if anything. Read on every request.
    var block: NetworkBlock? {
        lock.withLock {
            switch route {
            case .direct: systemBlock
            case .tunnelDown: .tunnelNotConnected
            // The tunnel is the VPN: a system VPN is not also required.
            case .tunnel: nil
            }
        }
    }

    /// Set by the "Require a VPN" check.
    func setSystemBlock(_ reason: NetworkBlock?) {
        lock.withLock { systemBlock = reason }
    }

    func setRoute(_ newRoute: Route) {
        lock.withLock {
            guard route != newRoute else { return }
            route = newRoute
            // Sessions already made carry the old proxy; the next request builds new ones.
            cached = nil
        }
    }

    /// The tunnel's proxy while traffic goes through it, for the players, which cannot use a session.
    var proxy: ProxyEndpoint? {
        lock.withLock {
            if case let .tunnel(endpoint) = route {
                endpoint
            } else {
                nil
            }
        }
    }

    /// Whether the app's tunnel is switched on (up or not), so players that cannot use a proxy stand aside.
    var tunnelIsOn: Bool {
        lock.withLock { route != .direct }
    }

    /// Throws while traffic is held back.
    func requireOpen() throws {
        if let block {
            throw block
        }
    }

    /// The portable core's transport: fails closed while `block` is set, and follows the route as it changes.
    var transport: any HTTPTransport {
        GuardedTransport(CurrentSessionTransport(network: self)) { [self] in block }
    }

    /// Artwork wants its own limits and no URL cache (the disk cache is ours), so it has its own session.
    var imageSession: URLSession {
        sessions().images
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try requireOpen()
        return try await sessions().standard.data(for: request)
    }

    fileprivate var standardSession: URLSession {
        sessions().standard
    }

    private func sessions() -> Sessions {
        lock.withLock {
            if let cached, cached.route == route {
                return cached.sessions
            }
            let made = Sessions(
                standard: URLSession(configuration: configuration(.default, for: route)),
                images: URLSession(configuration: Self.imageConfiguration(for: route, using: self))
            )
            cached = (route, made)
            return made
        }
    }

    private static func imageConfiguration(
        for route: Route,
        using network: ProviderNetwork
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 15
        return network.configuration(configuration, for: route)
    }

    /// With the tunnel up, every request on the session goes to its SOCKS5 proxy, and never falls back to direct.
    private func configuration(_ base: URLSessionConfiguration, for route: Route) -> URLSessionConfiguration {
        guard case let .tunnel(endpoint) = route,
              let port = NWEndpoint.Port(rawValue: UInt16(endpoint.socksPort))
        else {
            return base
        }
        var proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: .init(endpoint.host), port: port))
        proxy.applyCredential(username: endpoint.username, password: endpoint.password)
        proxy.allowFailover = false
        base.proxyConfigurations = [proxy]
        return base
    }
}

/// `URLSessionTransport` reads its session once; this takes the current one on every call, so a change of
/// route (the tunnel coming up, going down) applies to requests already being built by long-lived services.
private nonisolated struct CurrentSessionTransport: HTTPTransport { // swiftlint:disable:this modifier_order
    let network: ProviderNetwork

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await URLSessionTransport(session: network.standardSession).send(request)
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        try await URLSessionTransport(session: network.standardSession).stream(request)
    }
}
