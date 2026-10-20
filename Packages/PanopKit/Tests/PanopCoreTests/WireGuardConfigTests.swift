import Foundation
@testable import PanopCore
import Testing

private let key = Data(repeating: 7, count: 32).base64EncodedString()
private let otherKey = Data(repeating: 9, count: 32).base64EncodedString()

private func conf(
    interface: String = "PrivateKey = \(key)\nAddress = 10.2.0.2/32\nDNS = 10.2.0.1",
    peer: String = "PublicKey = \(otherKey)\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = 185.159.157.10:51820"
) -> String {
    "[Interface]\n\(interface)\n\n[Peer]\n\(peer)\n"
}

struct WireGuardConfigTests {
    @Test func `parses what Proton hands out`() throws {
        let text = """
        [Interface]
        # Key for Panop
        PrivateKey = \(key)
        Address = 10.2.0.2/32
        DNS = 10.2.0.1

        [Peer]
        # NL#12
        PublicKey = \(otherKey)
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 185.159.157.10:51820
        """
        let config = try WireGuardConfig.parse(text)
        #expect(config.addresses == ["10.2.0.2/32"])
        #expect(config.dns == ["10.2.0.1"])
        #expect(config.allowedIPs == ["0.0.0.0/0", "::/0"])
        #expect(config.endpointHost == "185.159.157.10")
    }

    @Test func `accepts CRLF line ends, several addresses and an IPv6 endpoint`() throws {
        let text = conf(
            interface: "PrivateKey = \(key)\nAddress = 10.2.0.2/32, fd00::2/128\nDNS = 10.2.0.1, fd00::1\nMTU = 1420",
            peer: "PublicKey = \(otherKey)\nPresharedKey = \(key)\nAllowedIPs = 0.0.0.0/0\n"
                + "Endpoint = [2001:db8::1]:51820\nPersistentKeepalive = 25"
        ).replacingOccurrences(of: "\n", with: "\r\n")
        let config = try WireGuardConfig.parse(text)
        #expect(config.addresses.count == 2)
        #expect(config.dns == ["10.2.0.1", "fd00::1"])
        #expect(config.mtu == 1420)
        #expect(config.presharedKey == key)
        #expect(config.endpointHost == "2001:db8::1")
        #expect(config.persistentKeepalive == 25)
    }

    @Test func `a hostname endpoint is kept as given`() throws {
        let config = try WireGuardConfig
            .parse(conf(peer: "PublicKey = \(otherKey)\nAllowedIPs = 0.0.0.0/0\nEndpoint = nl.example.net:51820"))
        #expect(config.endpointHost == "nl.example.net")
    }

    @Test func `an invalid key is reported by line and never echoed`() {
        let bad = "[Interface]\nPrivateKey = not-a-key-SECRETVALUE\n"
        do {
            _ = try WireGuardConfig.parse(bad)
            Issue.record("accepted")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Line 2"))
            #expect(!message.contains("SECRETVALUE"))
        }
    }

    @Test(arguments: [
        ("[Interface]\nAddress = 10.0.0.2/32\nDNS = 1.1.1.1\n", "PrivateKey"),
        ("[Interface]\nPrivateKey = KEY\nDNS = 1.1.1.1\n", "Address"),
        ("[Interface]\nPrivateKey = KEY\nAddress = 10.0.0.2/32\n", "DNS")
    ])
    func `a missing interface setting is named`(text: String, name: String) {
        let config = text.replacingOccurrences(of: "KEY", with: key)
        #expect(throws: WireGuardConfig.ParseError.self) { try WireGuardConfig.parse(config) }
        do { _ = try WireGuardConfig.parse(config) } catch { #expect("\(error)".contains(name)) }
    }

    @Test func `no peer, or two peers, is refused`() {
        #expect(throws: WireGuardConfig.ParseError.self) {
            try WireGuardConfig.parse("[Interface]\nPrivateKey = \(key)\nAddress = 10.0.0.2/32\nDNS = 1.1.1.1\n")
        }
        let twice = conf() + "\n[Peer]\nPublicKey = \(otherKey)\nAllowedIPs = 0.0.0.0/0\nEndpoint = 1.2.3.4:51820\n"
        #expect(throws: WireGuardConfig.ParseError.unsupported("More than one [Peer]")) {
            try WireGuardConfig.parse(twice)
        }
    }

    @Test func `an endpoint without a port, a bad address and a bad MTU are refused`() {
        #expect(throws: WireGuardConfig.ParseError.self) {
            try WireGuardConfig.parse(conf(peer: "PublicKey = \(otherKey)\nAllowedIPs = 0.0.0.0/0\nEndpoint = 1.2.3.4"))
        }
        #expect(throws: WireGuardConfig.ParseError.self) {
            try WireGuardConfig.parse(conf(interface: "PrivateKey = \(key)\nAddress = 10.2.0.999/32\nDNS = 10.2.0.1"))
        }
        #expect(throws: WireGuardConfig.ParseError.self) {
            try WireGuardConfig
                .parse(conf(interface: "PrivateKey = \(key)\nAddress = 10.2.0.2/32\nDNS = 10.2.0.1\nMTU = 20"))
        }
    }

    @Test func `the description and the rebuilt text carry no stray content, and the description no key`() throws {
        let config = try WireGuardConfig.parse(conf())
        #expect(!config.description.contains(key))
        #expect(!config.description.contains(otherKey))
        let again = try WireGuardConfig.parse(config.text)
        #expect(again == config)
    }
}
