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
}
