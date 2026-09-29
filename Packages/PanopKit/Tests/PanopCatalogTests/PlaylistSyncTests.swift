import Foundation
@testable import PanopCatalog
import PanopCore
import PanopXtream
import Testing

private let now = Date(timeIntervalSince1970: 1_790_640_000 + 12 * 3600)

private func stamp(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return String(
        format: "%04d%02d%02d%02d%02d00 +0000",
        parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
    )
}

/// A guide with `count` one-hour programmes starting an hour from `now`.
private func guideXML(count: Int = 6) -> String {
    var lines = [#"<tv><channel id="chan.0"><display-name>Channel 0</display-name></channel>"#]
    for index in 0 ..< count {
        let start = now.addingTimeInterval(TimeInterval((index + 1) * 3600))
        lines.append(
            #"<programme start="\#(stamp(start))" stop="\#(stamp(start.addingTimeInterval(3600)))" channel="chan.0">"#
                + "<title>Show \(index)</title></programme>"
        )
    }
    return lines.joined(separator: "\n") + "\n</tv>"
}

private func importer(_ store: any CatalogStore, _ handler: @escaping StubTransport.Handler) -> CatalogImporter {
    CatalogImporter(store: store, transport: StubTransport(handler: handler), now: { now })
}

@Suite("Playlist sync")
struct PlaylistSyncTests {
    // MARK: - M3U

    @Test
    func `imports the catalog and then the guide the header advertises`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile(livePlaylist(0 ..< 5, epgURL: "http://epg.example/guide.xml"))
        let sut = importer(store) { request in
            request.url.host == "epg.example" ? (200, guideXML()) : (404, "")
        }

        let outcome = try await sut.sync(PlaylistDescriptor(id: "p", source: .localM3U(path: path)))

        #expect(outcome.catalog.kinds.first?.imported == 5)
        guard case let .imported(guide) = outcome.guide else {
            Issue.record("expected an imported guide, got \(outcome.guide)")
            return
        }
        #expect(guide.programmes.inserted == 6)
        #expect(await store.allProgrammes(playlist: "p").count == 6)
    }

    @Test
    func `a configured guide URL wins over the header`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile(livePlaylist(0 ..< 2, epgURL: "http://header.example/guide.xml"))
        let sut = importer(store) { request in
            request.url.host == "mine.example" ? (200, guideXML(count: 3)) : (500, "")
        }

        let outcome = try await sut.sync(PlaylistDescriptor(
            id: "p",
            source: .localM3U(path: path),
            guideURL: "http://mine.example/epg.xml"
        ))

        guard case let .imported(guide) = outcome.guide else {
            Issue.record("got \(outcome.guide)")
            return
        }
        #expect(guide.programmes.inserted == 3)
    }

    @Test
    func `a playlist with no guide reports that instead of failing`() async throws {
        let path = try writeTemporaryFile(livePlaylist(0 ..< 2))
        let sut = importer(InMemoryCatalogStore()) { _ in (500, "") }

        let outcome = try await sut.sync(PlaylistDescriptor(id: "p", source: .localM3U(path: path)))

        #expect(outcome.guide == .noGuideAvailable)
    }

    /// The guide is a bonus. A broken one must not fail or undo the catalog.
    @Test
    func `a failing guide leaves the catalog import intact`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile(livePlaylist(0 ..< 5, epgURL: "http://epg.example/guide.xml"))
        let sut = importer(store) { _ in (503, "") }

        let outcome = try await sut.sync(PlaylistDescriptor(id: "p", source: .localM3U(path: path)))

        #expect(await store.allEntries(playlist: "p").count == 5)
        guard case let .failed(message) = outcome.guide else {
            Issue.record("got \(outcome.guide)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test
    func `a guide error message never contains the credentials in its URL`() async throws {
        let path = try writeTemporaryFile(
            livePlaylist(0 ..< 2, epgURL: "http://epg.example/guide.xml?user=alice&token=s3cret")
        )
        let sut = importer(InMemoryCatalogStore()) { request in
            throw NSError(
                domain: "t",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "failed: \(request.url.absoluteString)"]
            )
        }

        let outcome = try await sut.sync(PlaylistDescriptor(id: "p", source: .localM3U(path: path)))

        guard case let .failed(message) = outcome.guide else {
            Issue.record("got \(outcome.guide)")
            return
        }
        #expect(!message.contains("s3cret"))
        #expect(!message.contains("alice"))
    }

    /// The catalog file may be unchanged while the guide has moved on.
    @Test
    func `an unchanged playlist still refreshes its guide`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile(livePlaylist(0 ..< 5, epgURL: "http://epg.example/guide.xml"))
        let sut = importer(store) { _ in (200, guideXML()) }
        let descriptor = PlaylistDescriptor(id: "p", source: .localM3U(path: path))

        _ = try await sut.sync(descriptor)
        let second = try await sut.sync(descriptor)

        #expect(second.catalog.outcome == .unchanged)
        #expect(second.catalog.epgURLs == ["http://epg.example/guide.xml"])
        guard case let .imported(guide) = second.guide else {
            Issue.record("got \(second.guide)")
            return
        }
        #expect(guide.programmes.unchanged == 6)
    }

    @Test
    func `the guide can be skipped`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile(livePlaylist(0 ..< 2, epgURL: "http://epg.example/guide.xml"))
        let sut = importer(store) { _ in (200, guideXML()) }

        let outcome = try await sut.sync(PlaylistDescriptor(id: "p", source: .localM3U(path: path)), guide: false)

        #expect(outcome.guide == .noGuideAvailable)
        #expect(await store.allProgrammes(playlist: "p").isEmpty)
    }

    @Test
    func `a remote playlist is downloaded then its guide fetched`() async throws {
        let store = InMemoryCatalogStore()
        let playlist = livePlaylist(0 ..< 4, epgURL: "http://epg.example/guide.xml")
        let sut = importer(store) { request in
            switch request.url.host {
            case "epg.example": (200, guideXML())
            case "panel.example": (200, playlist)
            default: (404, "")
            }
        }

        let outcome = try await sut.sync(PlaylistDescriptor(
            id: "p",
            source: .remoteM3U("http://panel.example/get.php?username=alice&password=s3cret")
        ))

        #expect(outcome.catalog.kinds.first?.imported == 4)
        #expect(await store.allProgrammes(playlist: "p").count == 6)
    }

    @Test(arguments: ["", "not a url", "ftp://host/list.m3u", "http://"])
    func `an unusable source URL is rejected`(text: String) async {
        let sut = importer(InMemoryCatalogStore()) { _ in (200, "") }
        await #expect(throws: CatalogError.invalidSource) {
            _ = try await sut.sync(PlaylistDescriptor(id: "p", source: .remoteM3U(text)))
        }
    }

    // MARK: - Xtream

    @Test
    func `an Xtream playlist imports its lists and its own guide`() async throws {
        let store = InMemoryCatalogStore()
        let credentials = ProviderCredentials(baseURL: "http://panel.example", username: "alice", password: "s3cret")
        let sut = importer(store) { request in
            if request.url.path.hasSuffix("xmltv.php") {
                return (200, guideXML(count: 4))
            }
            switch query(request, "action") {
            case nil: return (200, #"{"user_info":{"auth":1}}"#)
            case "get_live_streams": return (200, #"[{"stream_id":1,"name":"One"},{"stream_id":2,"name":"Two"}]"#)
            default: return (200, "[]")
            }
        }

        let outcome = try await sut.sync(PlaylistDescriptor(id: "x", source: .xtream(credentials)))

        #expect(outcome.catalog.kinds.first { $0.kind == .live }?.imported == 2)
        guard case let .imported(guide) = outcome.guide else {
            Issue.record("got \(outcome.guide)")
            return
        }
        #expect(guide.programmes.inserted == 4)
    }

    @Test
    func `the Xtream guide URL carries encoded credentials`() throws {
        let client = try XtreamClient(
            credentials: ProviderCredentials(baseURL: "http://h:8080/", username: "a b", password: "p&ss+w"),
            transport: StubTransport { _ in (200, "") }
        )
        #expect(client.guideURL()?.absoluteString == "http://h:8080/xmltv.php?password=p%26ss%2Bw&username=a%20b")
    }

    // MARK: - Window and removal

    @Test
    func `the standard window looks back two hours and ahead two days`() {
        let window = GuideWindow.standard(around: now)
        #expect(window.lowerBound == now.addingTimeInterval(-2 * 3600))
        #expect(window.upperBound == now.addingTimeInterval(48 * 3600))
    }

    @Test
    func `removing a playlist deletes everything it owns and nothing else`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store) { _ in (200, guideXML()) }
        for id in ["a", "b"] {
            let path = try writeTemporaryFile(livePlaylist(0 ..< 5, epgURL: "http://epg.example/guide.xml"))
            _ = try await sut.sync(PlaylistDescriptor(id: id, source: .localM3U(path: path)))
        }

        try await store.removePlaylist("a")

        #expect(await store.allEntries(playlist: "a").isEmpty)
        #expect(await store.allCategories(playlist: "a").isEmpty)
        #expect(await store.allProgrammes(playlist: "a").isEmpty)
        #expect(await store.allEPGChannels(playlist: "a").isEmpty)
        #expect(await store.syncState(playlist: "a") == nil)
        #expect(await store.allEntries(playlist: "b").count == 5)
        #expect(await store.allProgrammes(playlist: "b").count == 6)
    }

    @Test
    func `URL secrets include user info and every query value`() throws {
        let url = try #require(URL(string: "http://bob:hunter2@host/list?user=alice&token=s3cret&empty="))
        #expect(Set(URLSecrets.values(in: url)) == ["bob", "hunter2", "alice", "s3cret"])
    }
}
