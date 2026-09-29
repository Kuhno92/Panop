/// How Panop reaches a provider.
///
/// Held as plain values here. Persistence and encryption are the app's concern,
/// because this type has to stay usable on platforms with no Keychain.
public struct ProviderCredentials: Sendable, Equatable, Hashable {
    /// Scheme and host, optionally with a port. No trailing path.
    public var baseURL: String
    public var username: String
    public var password: String

    public init(baseURL: String, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }
}

extension ProviderCredentials: CustomStringConvertible {
    /// Redacted on purpose. Credentials must never reach a log.
    public var description: String {
        "ProviderCredentials(baseURL: \(baseURL), username: <redacted>, password: <redacted>)"
    }
}

/// Where a playlist comes from.
public enum PlaylistSource: Sendable, Equatable, Hashable {
    /// A remote M3U/M3U8 URL.
    case remoteM3U(String)
    /// A local file, typically imported by the user.
    case localM3U(path: String)
    /// An Xtream Codes provider.
    case xtream(ProviderCredentials)
}
