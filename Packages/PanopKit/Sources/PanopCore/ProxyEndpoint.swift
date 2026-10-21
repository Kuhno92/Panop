import Foundation

/// Where the in-process tunnel listens, and the login that keeps other apps off it. Everything that carries
/// Panop's own traffic through the tunnel (URLSession, the players) is given one of these.
public struct ProxyEndpoint: Sendable, Equatable, CustomStringConvertible {
    public var host: String
    public var socksPort: Int
    public var httpPort: Int
    public var username: String
    public var password: String
    /// The relay (see `relayURL`): zero where the tunnel has none.
    public var relayPort: Int
    public var relaySecret: String

    public init(
        host: String = "127.0.0.1",
        socksPort: Int,
        httpPort: Int,
        username: String,
        password: String,
        relayPort: Int = 0,
        relaySecret: String = ""
    ) {
        self.host = host
        self.socksPort = socksPort
        self.httpPort = httpPort
        self.username = username
        self.password = password
        self.relayPort = relayPort
        self.relaySecret = relaySecret
    }

    /// The address to give a player that cannot use a proxy (AVPlayer, VLC, AetherEngine): an address on this
    /// device, which the tunnel's relay answers by fetching the real one through the VPN.
    /// `http://127.0.0.1:<port>/<secret>/<base64url of the address>/<name>`, the name being the address's last path
    /// component so the player still sees `.m3u8` or `.ts`. Nil where there is no relay or the address is not http(s).
    public func relayURL(for address: String) -> String? {
        guard relayPort > 0, !relaySecret.isEmpty, let url = URL(string: address),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        let encoded = Data(address.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let last = url.path.split(separator: "/").last.map(String.init) ?? ""
        let name = last.isEmpty ? "stream" : last
        let safe = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F") ?? "stream"
        return "http://\(host):\(relayPort)/\(relaySecret)/\(encoded)/\(safe)"
    }

    /// `http://user:pass@127.0.0.1:port`, the form FFmpeg's `http_proxy` option and libVLC take.
    public var httpURL: String {
        "http://\(username):\(password)@\(host):\(httpPort)"
    }

    /// Where an address leads, as far as its text says: a name is taken for the internet (only a lookup can tell
    /// otherwise), an IP address is placed by its range.
    public enum Locality: Sendable, Equatable {
        case internet
        /// 10.x, 172.16-31.x, 192.168.x, 169.254.x, fe80:, fc00::/7: the local network, which a VPN does not reach.
        case privateNetwork
        /// This device itself.
        case loopback
        /// A `.local` (Bonjour) name: on the local network.
        case localName
        /// Not an http or https address (a file, a custom scheme, nothing).
        case notWeb
    }

    public static func locality(of address: String) -> Locality {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return .notWeb }
        let host = url.host?.lowercased() ?? ""
        if host.isEmpty {
            return .notWeb
        }
        return locality(ofHost: host)
    }

    public static func locality(ofHost host: String) -> Locality {
        if host == "localhost" || host == "::1" {
            return .loopback
        }
        if host.hasSuffix(".local") {
            return .localName
        }
        if host.contains(":") {
            if host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
                return .privateNetwork
            }
            return .internet
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return .internet }
        switch (parts[0], parts[1]) {
        case (127, _): return .loopback
        case (10, _), (192, 168), (169, 254): return .privateNetwork
        case (172, 16 ... 31): return .privateNetwork
        default: return .internet
        }
    }

    /// Whether a stream address should go through the proxy: only an address on the internet. Loopback,
    /// private-network addresses and local files do not (the tunnel leads out to the internet, and URLSession itself
    /// skips a proxy for them, so they would not be consistent).
    public static func applies(to address: String) -> Bool {
        locality(of: address) == .internet
    }

    /// `scheme://host:port` and nothing else: an address carries the account's login in its path or user part, and
    /// anything shown or copied must not.
    public static func redacted(_ address: String) -> String? {
        guard let url = URL(string: address), let scheme = url.scheme, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        let shown = host.contains(":") ? "[\(host)]" : host
        return "\(scheme)://\(shown)\(port)"
    }

    /// Never shows the login.
    public var description: String {
        "ProxyEndpoint(\(host):\(socksPort)/\(httpPort)/\(relayPort), login: redacted)"
    }
}
