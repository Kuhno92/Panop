import Foundation

/// Where the in-process tunnel listens, and the login that keeps other apps off it. Everything that carries
/// Panop's own traffic through the tunnel (URLSession, the players) is given one of these.
public struct ProxyEndpoint: Sendable, Equatable, CustomStringConvertible {
    public var host: String
    public var socksPort: Int
    public var httpPort: Int
    public var username: String
    public var password: String

    public init(host: String = "127.0.0.1", socksPort: Int, httpPort: Int, username: String, password: String) {
        self.host = host
        self.socksPort = socksPort
        self.httpPort = httpPort
        self.username = username
        self.password = password
    }

    /// `http://user:pass@127.0.0.1:port`, the form FFmpeg's `http_proxy` option and libVLC take.
    public var httpURL: String {
        "http://\(username):\(password)@\(host):\(httpPort)"
    }

    /// Whether a stream address should go through the proxy. Loopback and local files do not: the tunnel
    /// leads out to the internet, and a local address has nothing to do there.
    public static func applies(to address: String) -> Bool {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        let host = url.host?.lowercased() ?? ""
        return !(host == "localhost" || host == "127.0.0.1" || host == "::1" || host.isEmpty)
    }

    /// Never shows the login.
    public var description: String {
        "ProxyEndpoint(\(host):\(socksPort)/\(httpPort), login: redacted)"
    }
}
