import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

@Suite("Player window")
struct PlayerWindowTests {
    private let target = PlaybackTarget(
        playlist: "home",
        entryID: "live:42",
        kind: .live,
        name: "Das Erste",
        streamURL: "http://alice:s3cret@provider.example/live/alice/s3cret/42.ts",
        remoteID: "42",
        containerExtension: "ts",
        resumeAt: 120
    )

    /// A window's value is saved by the system to restore it, so it must not hold a login.
    @Test
    func `a window request holds no stream address, and so no login`() throws {
        let request = PlayerWindowRequest(target)

        let encoded = try JSONEncoder().encode(request)
        let json = try #require(String(bytes: encoded, encoding: .utf8))

        #expect(!json.contains("s3cret"))
        #expect(!json.contains("alice"))
        #expect(!json.contains("http"))
        #expect(!json.contains("provider.example"))
    }

    @Test
    func `it survives being saved and restored`() throws {
        let request = PlayerWindowRequest(target)

        let restored = try JSONDecoder().decode(PlayerWindowRequest.self, from: JSONEncoder().encode(request))

        #expect(restored == request)
    }

    @Test
    func `the target comes back with the address it is given and everything else it had`() {
        let request = PlayerWindowRequest(target)

        let back = request.target(streamURL: "http://other/1.ts")

        #expect(back.playlist == "home")
        #expect(back.entryID == "live:42")
        #expect(back.kind == .live)
        #expect(back.name == "Das Erste")
        #expect(back.remoteID == "42")
        #expect(back.resumeAt == 120)
        #expect(back.streamURL == "http://other/1.ts")
    }

    @Test
    func `the same item is the same window value, so opening it twice finds the open window`() {
        #expect(PlayerWindowRequest(target) == PlayerWindowRequest(target))
        #expect(PlayerWindowRequest(target).hashValue == PlayerWindowRequest(target).hashValue)
    }

    // MARK: - Episodes

    /// An episode is not a catalog row, so its address is rebuilt from the playlist's own login and
    /// its own id, which is a string on some panels.
    @Test
    func `an episode's address is rebuilt from the playlist login and its id`() throws {
        let episode = PlaybackTarget(
            playlist: "home",
            entryID: "episode:ep-17",
            kind: .series,
            name: "Dark · S1E1",
            remoteID: "ep-17",
            containerExtension: "mkv",
            resumeAt: 300
        )
        let source = PlaylistSource.xtream(ProviderCredentials(
            baseURL: "http://panel.example:8080", username: "alice", password: "s3cret"
        ))

        let request = try PlaybackRequestBuilder.request(
            for: episode,
            source: source,
            transport: StubTransport { _ in (404, "") }
        )
        let item = request.item(.avPlayer)

        #expect(item.url == "http://panel.example:8080/series/alice/s3cret/ep-17.mkv")
        #expect(item.startPosition == 300)
    }

    @Test
    func `an episode with no login cannot be played, and says why`() {
        let episode = PlaybackTarget(
            playlist: "home", entryID: "episode:1", kind: .series, name: "E", remoteID: "1", containerExtension: "mp4"
        )

        #expect(throws: PlaybackTargetError.self) {
            try PlaybackRequestBuilder.request(for: episode, source: nil, transport: StubTransport { _ in (404, "") })
        }
    }

    #if os(macOS)

        // MARK: - Finding the address again

        @Test
        @MainActor
        func `the catalog gives back the address of the right playlist's item`() throws {
            let container = try PanopContainers.makeCatalog(inMemory: true)
            let context = ModelContext(container)
            context.insert(CatalogEntryRecord(
                playlist: "home",
                entry: CatalogEntry(id: "42", kind: .live, name: "A", streamURL: "http://home.example/42.ts")
            ))
            context.insert(CatalogEntryRecord(
                playlist: "backup",
                entry: CatalogEntry(id: "42", kind: .live, name: "A", streamURL: "http://backup.example/42.ts")
            ))
            try context.save()
            func request(_ playlist: String, _ entry: String) -> PlayerWindowRequest {
                PlayerWindowRequest(PlaybackTarget(playlist: playlist, entryID: entry, kind: .live, name: "A"))
            }

            #expect(PlayerWindowContent
                .streamURL(for: request("home", "42"), in: context) == "http://home.example/42.ts")
            #expect(PlayerWindowContent
                .streamURL(for: request("backup", "42"), in: context) == "http://backup.example/42.ts")
            #expect(PlayerWindowContent.streamURL(for: request("home", "missing"), in: context) == nil)
        }
    #endif
}
