import Foundation
@testable import Panop
import PanopCore
import Testing

@Suite("Playlist links the app refuses")
@MainActor
struct PlaylistLinkRefusalTests {
    @Test
    func `a GitHub page is refused with what to use instead, and nothing is stored`() async throws {
        let app = try TestApp(transport: FakePanel(live: 1, movies: 0).transport())
        defer { app.cleanUp() }

        let error = await #expect(throws: PlaylistAddError.self) {
            try await app.services.library.add(.m3uURL(
                name: "",
                url: "https://github.com/iptv-org/iptv/blob/master/streams/de.m3u",
                guideURL: nil
            ))
        }

        #expect(error?.message.contains("raw.githubusercontent.com") == true)
        #expect(app.services.library.playlists.isEmpty)
        #expect(try app.storedRecords().isEmpty)
    }

    @Test
    func `the raw address is accepted`() async throws {
        let app = try TestApp(transport: FakePanel(live: 1, movies: 0).transport())
        defer { app.cleanUp() }

        let added = try await app.services.library.add(.m3uURL(
            name: "Germany",
            url: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/de.m3u",
            guideURL: nil
        ))

        #expect(added.displayHost == "raw.githubusercontent.com")
    }
}
