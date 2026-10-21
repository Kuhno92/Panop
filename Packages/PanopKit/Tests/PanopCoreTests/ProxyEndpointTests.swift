import Foundation
@testable import PanopCore
import Testing

struct ProxyEndpointTests {
    private let endpoint = ProxyEndpoint(socksPort: 1080, httpPort: 8080, username: "u", password: "SECRET")

    @Test func `the HTTP form carries the login for the players`() {
        #expect(endpoint.httpURL == "http://u:SECRET@127.0.0.1:8080")
    }

    @Test func `the description never shows the login`() {
        #expect(!endpoint.description.contains("SECRET"))
    }

    @Test(arguments: [
        "http://provider.example/live/1.ts",
        "https://provider.example/x.m3u8",
        "http://203.0.113.5:8000/a"
    ])
    func `internet streams go through the proxy`(address: String) {
        #expect(ProxyEndpoint.applies(to: address))
    }

    @Test(arguments: [
        "file:///tmp/a.ts",
        "http://127.0.0.1:9000/a",
        "http://localhost/a",
        "rtsp://host/a",
        "not a url",
        ""
    ])
    func `local and non-HTTP addresses do not`(address: String) {
        #expect(!ProxyEndpoint.applies(to: address))
    }

    @Test func `addresses just outside the private ranges are internet addresses`() {
        #expect(ProxyEndpoint.applies(to: "http://172.32.0.1/a"))
        #expect(ProxyEndpoint.applies(to: "http://192.169.0.1/a"))
        #expect(ProxyEndpoint.applies(to: "http://11.0.0.1/a"))
    }

    @Test(arguments: [
        ("http://203.0.113.5/a", ProxyEndpoint.Locality.internet), ("https://provider.example/a", .internet),
        ("http://192.168.178.1:8080/a", .privateNetwork), ("http://10.1.2.3/a", .privateNetwork),
        ("http://172.16.0.1/a", .privateNetwork), ("http://169.254.9.9/a", .privateNetwork),
        ("http://[fd12::1]/a", .privateNetwork), ("http://[2001:db8::1]/a", .internet),
        ("http://127.0.0.1/a", .loopback), ("http://localhost/a", .loopback), ("http://[::1]/a", .loopback),
        ("http://nas.local/a", .localName), ("file:///a.ts", .notWeb), ("rtsp://x/a", .notWeb)
    ])
    func `an address is placed`(address: String, place: ProxyEndpoint.Locality) {
        #expect(ProxyEndpoint.locality(of: address) == place)
    }

    @Test func `a shown address has no login and no path`() {
        #expect(ProxyEndpoint
            .redacted("http://user:secret@host.example:8000/live/user/secret/12.ts") == "http://host.example:8000")
        #expect(ProxyEndpoint.redacted("https://host.example/live/user/secret/12.m3u8") == "https://host.example")
        #expect(ProxyEndpoint.redacted("http://[2001:db8::1]:80/x") == "http://[2001:db8::1]:80")
        #expect(ProxyEndpoint.redacted("not a url") == nil)
    }

    private let relayed = ProxyEndpoint(
        socksPort: 1, httpPort: 2, username: "u", password: "SECRET", relayPort: 9000, relaySecret: "abc123"
    )

    @Test func `a relay address carries the real one, encoded, and keeps the extension`() throws {
        let address = "http://provider.example:8000/live/user/pass/12.ts?token=a&b=1"
        let relay = try #require(relayed.relayURL(for: address))
        #expect(relay.hasPrefix("http://127.0.0.1:9000/abc123/"))
        #expect(relay.hasSuffix("/12.ts"))
        let encoded = relay.split(separator: "/")[3]
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        #expect(try String(data: #require(Data(base64Encoded: base64)), encoding: .utf8) == address)
    }

    @Test func `there is no relay address without a relay, or for what is not http`() {
        #expect(ProxyEndpoint(socksPort: 1, httpPort: 2, username: "u", password: "p")
            .relayURL(for: "http://h/a.ts") == nil)
        #expect(relayed.relayURL(for: "file:///a.ts") == nil)
        #expect(relayed.relayURL(for: "rtsp://h/a") == nil)
    }

    @Test func `an address with no path gets a plain name`() throws {
        #expect(try #require(relayed.relayURL(for: "http://h:80")).hasSuffix("/stream"))
    }

    @Test func `the description never shows the relay secret`() {
        #expect(!relayed.description.contains("abc123"))
    }
}
