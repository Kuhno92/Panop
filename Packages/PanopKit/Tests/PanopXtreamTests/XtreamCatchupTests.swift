import Foundation
import PanopCore
@testable import PanopXtream
import Testing

@Suite("Xtream catch-up")
struct XtreamCatchupTests {
    private func client() throws -> XtreamClient {
        try XtreamClient(
            credentials: ProviderCredentials(baseURL: "http://p.example:8080", username: "alice", password: "s3 cret"),
            transport: StubTransport(body: "{}")
        )
    }

    /// 2026-05-01 18:30 UTC.
    private let start = Date(timeIntervalSince1970: 1_777_660_200)

    @Test
    func `the address names the minute, the length and the stream, in the panel's time zone`() throws {
        let berlin = TimeZone(identifier: "Europe/Berlin")
        let url = try #require(client().catchupURL(streamID: 77, start: start, minutes: 45, timeZone: berlin))

        // Berlin is two hours ahead of UTC in May.
        #expect(url.absoluteString == "http://p.example:8080/timeshift/alice/s3%20cret/45/2026-05-01:20-30/77.ts")
    }

    @Test
    func `with no zone known it is written in UTC`() throws {
        let url = try #require(client().catchupURL(streamID: 1, start: start, minutes: 30, timeZone: nil))

        #expect(url.absoluteString.contains("/2026-05-01:18-30/"))
    }

    @Test
    func `a length under a minute is a minute`() throws {
        let url = try #require(client().catchupURL(streamID: 1, start: start, minutes: 0, timeZone: nil))

        #expect(url.absoluteString.contains("/1/2026-05-01:"))
    }

    @Test
    func `the panel's time zone is read from the login answer`() async throws {
        let body = """
        {"user_info":{"username":"alice","auth":1,"status":"Active"},"server_info":{"timezone":"Europe/Berlin"}}
        """
        let client = try XtreamClient(
            credentials: ProviderCredentials(baseURL: "http://p.example", username: "alice", password: "pw"),
            transport: StubTransport(body: body)
        )

        let account = try await client.authenticate()

        #expect(account.timeZoneID == "Europe/Berlin")
    }
}
