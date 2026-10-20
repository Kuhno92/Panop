import Foundation

/// A standard WireGuard `.conf` (what Proton, Mullvad and the others hand out), checked before the tunnel is
/// started so the person gets a plain reason instead of a tunnel that silently does not come up.
///
/// It holds a private key, so it never prints one: `description` is redacted, and errors name a line, never a
/// value.
public struct WireGuardConfig: Sendable, Equatable, CustomStringConvertible {
    public enum ParseError: Error, Sendable, Equatable, CustomStringConvertible {
        case line(Int, String)
        case missing(String)
        case unsupported(String)

        public var description: String {
            switch self {
            case let .line(number, reason): "Line \(number): \(reason)"
            case let .missing(what): "Missing \(what)."
            case let .unsupported(what): "\(what) is not supported."
            }
        }
    }

    public var privateKey: String
    public var addresses: [String]
    public var dns: [String]
    public var mtu: Int?
    public var publicKey: String
    public var presharedKey: String?
    public var endpoint: String
    public var allowedIPs: [String]
    public var persistentKeepalive: Int?

    /// The server's host or address, for showing "connected to ..." without the port or any key.
    public var endpointHost: String {
        if endpoint.hasPrefix("["), let close = endpoint.firstIndex(of: "]") {
            return String(endpoint[endpoint.index(after: endpoint.startIndex) ..< close])
        }
        return endpoint.split(separator: ":", omittingEmptySubsequences: false).dropLast().joined(separator: ":")
    }

    public var description: String {
        "WireGuardConfig(endpoint: \(endpointHost), keys: redacted)"
    }

    /// The configuration text for the tunnel. Rebuilt rather than kept, so that comments and unknown
    /// keys the person pasted are not carried along.
    public var text: String {
        var lines = ["[Interface]", "PrivateKey = \(privateKey)", "Address = \(addresses.joined(separator: ", "))"]
        lines.append("DNS = \(dns.joined(separator: ", "))")
        if let mtu {
            lines.append("MTU = \(mtu)")
        }
        lines += ["", "[Peer]", "PublicKey = \(publicKey)"]
        if let presharedKey {
            lines.append("PresharedKey = \(presharedKey)")
        }
        lines.append("AllowedIPs = \(allowedIPs.joined(separator: ", "))")
        lines.append("Endpoint = \(endpoint)")
        if let persistentKeepalive {
            lines.append("PersistentKeepalive = \(persistentKeepalive)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func parse(_ text: String) throws -> WireGuardConfig {
        var section = ""
        var interface: [String: String] = [:]
        var peers: [[String: String]] = []
        for (index, raw) in text.replacingOccurrences(of: "\r", with: "").split(
            separator: "\n", omittingEmptySubsequences: false
        ).enumerated() {
            let number = index + 1
            var line = raw.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#") {
                line = line[..<hash].trimmingCharacters(in: .whitespaces)
            }
            if line.isEmpty {
                continue
            }
            if line.hasPrefix("[") {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).lowercased()
                switch section {
                case "interface": break
                case "peer": peers.append([:])
                default: throw ParseError.line(number, "unknown section")
                }
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { throw ParseError.line(number, "expected Key = Value") }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            switch section {
            case "interface":
                try check(key: key, value: value, line: number)
                interface[key] = value
            case "peer":
                try check(key: key, value: value, line: number)
                peers[peers.count - 1][key] = value
            default:
                throw ParseError.line(number, "a setting before any section")
            }
        }
        return try assemble(interface: interface, peers: peers)
    }

    private static func check(key: String, value: String, line: Int) throws {
        switch key {
        case "privatekey", "publickey", "presharedkey":
            guard Data(base64Encoded: value)?.count == 32 else { throw ParseError.line(line, "not a valid key") }
        case "mtu", "persistentkeepalive":
            guard Int(value) != nil else { throw ParseError.line(line, "not a number") }
        case "address", "allowedips":
            for item in list(value) where !isCIDR(item) {
                throw ParseError.line(line, "not an address")
            }
        default:
            break
        }
    }

    private static func assemble(interface: [String: String], peers: [[String: String]]) throws -> WireGuardConfig {
        guard let privateKey = interface["privatekey"] else { throw ParseError.missing("PrivateKey") }
        guard let address = interface["address"] else { throw ParseError.missing("Address") }
        // Names are looked up inside the tunnel, so it needs a server to ask.
        let dns = list(interface["dns"] ?? "").filter(isIP)
        guard !dns.isEmpty else { throw ParseError.missing("DNS address") }
        guard peers.count == 1, let peer = peers.first else {
            throw peers.isEmpty ? ParseError.missing("[Peer]") : ParseError.unsupported("More than one [Peer]")
        }
        guard let publicKey = peer["publickey"] else { throw ParseError.missing("PublicKey") }
        guard let endpoint = peer["endpoint"],
              endpointPort(endpoint) != nil else { throw ParseError.missing("Endpoint") }
        guard let allowed = peer["allowedips"] else { throw ParseError.missing("AllowedIPs") }
        let mtu = interface["mtu"].flatMap(Int.init)
        if let mtu, !(576 ... 1500).contains(mtu) {
            throw ParseError.unsupported("This MTU")
        }
        return WireGuardConfig(
            privateKey: privateKey, addresses: list(address), dns: dns, mtu: mtu,
            publicKey: publicKey, presharedKey: peer["presharedkey"], endpoint: endpoint,
            allowedIPs: list(allowed), persistentKeepalive: peer["persistentkeepalive"].flatMap(Int.init)
        )
    }

    private static func list(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func isIP(_ text: String) -> Bool {
        text.contains(":") ? text.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." } && text.contains(":")
            : isIPv4(text)
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0 ... 255).contains($0) } ?? false }
    }

    private static func isCIDR(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let bits = Int(parts[1]) else { return false }
        let address = String(parts[0])
        return address.contains(":") ? isIP(address) && (0 ... 128).contains(bits) : isIPv4(address) && (0 ... 32)
            .contains(bits)
    }

    /// The port of `host:port` or `[v6]:port`, or nil when there is none.
    private static func endpointPort(_ endpoint: String) -> Int? {
        guard let colon = endpoint.lastIndex(of: ":"), colon != endpoint.startIndex else { return nil }
        guard let port = Int(endpoint[endpoint.index(after: colon)...]),
              (1 ... 65535).contains(port) else { return nil }
        return port
    }
}
