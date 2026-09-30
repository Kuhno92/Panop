import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

/// The structure of a real multivariant playlist from an Akamai-hosted broadcaster: separate
/// audio groups, redundant variants, and root-relative variant paths.
private let hlsMultivariant = """
#EXTM3U

#EXT-X-INDEPENDENT-SEGMENTS

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="A1",NAME="TV Ton",LANGUAGE="deu",DEFAULT=YES,URI="/hls/live/2016501/dach/x/4/4.m3u8"
#EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=1173371,AUDIO="A1",RESOLUTION=640x360
/hls/live/2016501/dach/x/1/1.m3u8
#EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=1173371,AUDIO="A1",RESOLUTION=640x360
/hls/live/2016501-b/dach/x/1/1.m3u8
#EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=2257198,AUDIO="A1",RESOLUTION=960x540
/hls/live/2016501/dach/x/2/2.m3u8
"""

private let streamURL = "https://zdf-hls-18.akamaized.net/hls/live/2016501/dach/high/master.m3u8"

private func importer(_ store: InMemoryCatalogStore, serving body: String) -> CatalogImporter {
    CatalogImporter(store: store, transport: StubTransport { _ in (200, body) })
}

@Suite("Importing a stream URL and relative addresses")
struct HLSImportTests {
    // MARK: - An HLS manifest is one stream, not a playlist

    /// What happened when this was added as an "M3U link": six rows called `1.m3u8`,
    /// `2.m3u8` with addresses that had no host, which no engine could open.
    @Test
    func `an HLS multivariant playlist becomes one channel, not its variant lines`() async throws {
        let store = InMemoryCatalogStore()
        let url = try #require(URL(string: streamURL))

        let report = try await importer(store, serving: hlsMultivariant).importM3U(
            playlist: "p",
            source: .remote(url),
            streamName: "ZDF"
        )

        let entries = await store.allEntries(playlist: "p")
        #expect(entries.count == 1)
        let channel = try #require(entries.first)
        #expect(channel.name == "ZDF")
        #expect(channel.kind == .live)
        #expect(channel.streamURL == streamURL, "the channel must play the address the user gave")
        #expect(entries.allSatisfy { $0.streamURL?.hasPrefix("http") == true })
        #expect(report.skippedEntries == 0)
    }

    @Test
    func `the channel is named after the host when no name is given`() async throws {
        let store = InMemoryCatalogStore()
        let url = try #require(URL(string: streamURL))
        _ = try await importer(store, serving: hlsMultivariant).importM3U(playlist: "p", source: .remote(url))
        #expect(await store.allEntries(playlist: "p").first?.name == "zdf-hls-18.akamaized.net")
    }

    @Test
    func `a finished HLS recording is a movie`() async throws {
        let store = InMemoryCatalogStore()
        let vod = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6.0,\na.ts\n#EXT-X-ENDLIST\n"
        let url = try #require(URL(string: "https://host/show.m3u8"))

        _ = try await importer(store, serving: vod).importM3U(playlist: "p", source: .remote(url), streamName: "Show")

        #expect(await store.allEntries(playlist: "p").map(\.kind) == [.movie])
    }

    @Test
    func `importing the same stream again changes nothing`() async throws {
        let store = InMemoryCatalogStore()
        let url = try #require(URL(string: streamURL))
        let sut = importer(store, serving: hlsMultivariant)
        _ = try await sut.importM3U(playlist: "p", source: .remote(url), streamName: "ZDF")
        let writes = await store.writeCount

        let again = try await sut.importM3U(playlist: "p", source: .remote(url), streamName: "ZDF")

        #expect(again.outcome == .unchanged)
        #expect(await store.writeCount == writes)
    }

    /// Someone who already added the stream as a playlist has six dead rows. Refreshing
    /// must clear them and leave the one real channel.
    @Test
    func `refreshing a playlist that was imported the old way removes the dead rows`() async throws {
        let store = InMemoryCatalogStore()
        let dead = (1 ... 6).map {
            CatalogEntry(
                id: CatalogID.m3u(url: "/hls/live/x/\($0)/\($0).m3u8"),
                kind: .live,
                name: "\($0).m3u8",
                streamURL: "/hls/live/x/\($0)/\($0).m3u8"
            )
        }
        _ = try await store.upsertEntries(dead, playlist: "p")
        let url = try #require(URL(string: streamURL))

        let report = try await importer(store, serving: hlsMultivariant).importM3U(
            playlist: "p",
            source: .remote(url),
            force: true,
            streamName: "ZDF"
        )

        let remaining = await store.allEntries(playlist: "p")
        #expect(remaining.map(\.streamURL) == [streamURL])
        #expect(report.kinds.first { $0.kind == .live }?.removed == 6)
    }

    @Test
    func `a local HLS file is one channel pointing at the file`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile(hlsMultivariant)
        _ = try await CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
            .importM3U(playlist: "p", source: .file(path: path), streamName: "Local")

        let entries = await store.allEntries(playlist: "p")
        #expect(entries.count == 1)
        #expect(entries.first?.streamURL?.hasPrefix("file://") == true)
    }

    // MARK: - Real playlists are untouched

    @Test
    func `an ordinary playlist is still imported as channels`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile(livePlaylist(0 ..< 5))
        let report = try await CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
            .importM3U(playlist: "p", source: .file(path: path), streamName: "ignored")

        #expect(await store.allEntries(playlist: "p").count == 5)
        #expect(report.skippedEntries == 0)
    }

    // MARK: - Relative addresses

    @Test
    func `relative addresses resolve against the playlist's own address`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1,Root relative
        /live/1.ts
        #EXTINF:-1,Sibling
        sub/2.ts
        #EXTINF:-1,Absolute
        http://other.example/3.ts
        """
        let url = try #require(URL(string: "http://host.example/dir/list.m3u"))

        let report = try await importer(store, serving: text).importM3U(playlist: "p", source: .remote(url))

        let addresses = await Set(store.allEntries(playlist: "p").compactMap(\.streamURL))
        #expect(addresses == [
            "http://host.example/live/1.ts",
            "http://host.example/dir/sub/2.ts",
            "http://other.example/3.ts"
        ])
        #expect(report.skippedEntries == 0)
    }

    @Test
    func `an entry that cannot be made absolute is skipped and counted`() async throws {
        let store = InMemoryCatalogStore()
        // A file has no address to resolve a relative path against.
        let path = try writeTemporaryFile("#EXTM3U\n#EXTINF:-1,Relative\n/live/1.ts\n#EXTINF:-1,Good\nhttp://h/2.ts\n")

        let report = try await CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
            .importM3U(playlist: "p", source: .file(path: path))

        #expect(await store.allEntries(playlist: "p").map(\.name) == ["Good"])
        #expect(report.skippedEntries == 1)
    }

    @Test(arguments: [
        "udp://@239.1.1.1:1234",
        "rtmp://host/app/stream",
        "rtsp://cam/stream",
        "rtp://@239.0.0.1:5000",
        "http://h/a.ts"
    ])
    func `addresses with other streaming schemes are kept as written`(address: String) async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile("#EXTM3U\n#EXTINF:-1,Stream\n\(address)\n")
        _ = try await CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
            .importM3U(playlist: "p", source: .file(path: path))
        #expect(await store.allEntries(playlist: "p").first?.streamURL == address)
    }

    /// Identity hashes the address text, so resolving an already-absolute address
    /// must not rewrite it (favourites are keyed by the id).
    @Test
    func `an absolute address keeps the identity it always had`() async throws {
        let store = InMemoryCatalogStore()
        let address = "http://host/live/u/p/1.ts?token=a%20b&x=1"
        let path = try writeTemporaryFile("#EXTM3U\n#EXTINF:-1,One\n\(address)\n")
        _ = try await CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
            .importM3U(playlist: "p", source: .file(path: path))
        #expect(await store.allEntries(playlist: "p").first?.id == CatalogID.m3u(url: address))
    }

    @Test
    func `sync passes the playlist name to a single stream`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store, serving: hlsMultivariant)

        _ = try await sut.sync(
            PlaylistDescriptor(id: "p", source: .remoteM3U(streamURL), name: "My Stream"),
            guide: false
        )

        #expect(await store.allEntries(playlist: "p").map(\.name) == ["My Stream"])
    }
}
