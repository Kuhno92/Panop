import Foundation
@testable import PanopCatalog
import PanopCore
import PanopEPG
import Testing

private let playlistID = "e1"
private let guideURL = URL(string: "http://panel.example/xmltv.php?username=alice&password=s3cret") ??
    URL(fileURLWithPath: "/")

/// 2026-09-29 00:00 UTC.
private let dayStart = Date(timeIntervalSince1970: 1_790_640_000)

/// A guide with `count` one-hour programmes on `channel`, the first at `hour`.
private func guide(channel: String = "ard.de", hours: Range<Int>, title: (Int) -> String = { "Show \($0)" }) -> String {
    var lines = [#"<tv><channel id="\#(channel)"><display-name>ARD</display-name></channel>"#]
    for hour in hours {
        let start = String(format: "202609%02d%02d0000 +0000", 29 + hour / 24, hour % 24)
        let stop = String(format: "202609%02d%02d0000 +0000", 29 + (hour + 1) / 24, (hour + 1) % 24)
        lines
            .append(
                #"<programme start="\#(start)" stop="\#(stop)" channel="\#(channel)"><title>\#(title(hour))</title></programme>"#
            )
    }
    lines.append("</tv>")
    return lines.joined(separator: "\n")
}

private func importer(_ store: any CatalogStore, body: String) -> CatalogImporter {
    CatalogImporter(store: store, transport: StubTransport(chunkSize: 256) { _ in (200, body) }, batchSize: 10)
}

private let wholeDay = dayStart ... dayStart.addingTimeInterval(48 * 3600)

@Suite("EPG import")
struct EPGImportTests {
    @Test
    func `imports channels and programmes`() async throws {
        let store = InMemoryCatalogStore()
        let report = try await importer(store, body: guide(hours: 0 ..< 6))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        #expect(report.channels == 1)
        #expect(report.programmes.inserted == 6)
        #expect(await store.allProgrammes(playlist: playlistID).map(\.title) == (0 ..< 6).map { "Show \($0)" })
        #expect(await store.allEPGChannels(playlist: playlistID).map(\.id) == ["ard.de"])
    }

    @Test
    func `an unchanged guide writes nothing`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store, body: guide(hours: 0 ..< 30))
        _ = try await sut.importEPG(playlist: playlistID, url: guideURL, window: wholeDay)
        let writes = await store.writeCount

        let report = try await sut.importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        #expect(report.programmes.unchanged == 30)
        #expect(await store.writeCount == writes)
    }

    @Test
    func `programmes that have ended are dropped`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, body: guide(hours: 0 ..< 10))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        // A day later, the first ten hours are history.
        let later = dayStart.addingTimeInterval(8 * 3600) ... dayStart.addingTimeInterval(56 * 3600)
        let report = try await importer(store, body: guide(hours: 8 ..< 12))
            .importEPG(playlist: playlistID, url: guideURL, window: later)

        #expect(report.removedExpired == 8)
        #expect(await store.allProgrammes(playlist: playlistID).map(\.title) == [
            "Show 8",
            "Show 9",
            "Show 10",
            "Show 11"
        ])
    }

    /// The provider moved a programme. The old row must go, not sit beside the
    /// new one as a phantom overlap.
    @Test
    func `a rescheduled programme replaces the old one`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, body: guide(hours: 0 ..< 10))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        let report = try await importer(store, body: guide(hours: 0 ..< 8))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        #expect(report.removedStale == 2)
        #expect(await store.allProgrammes(playlist: playlistID).count == 8)
    }

    @Test
    func `an edited title is an update not a duplicate`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, body: guide(hours: 0 ..< 5))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        let report = try await importer(store, body: guide(hours: 0 ..< 5) { "Renamed \($0)" })
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        #expect(report.programmes.updated == 5)
        #expect(await store.allProgrammes(playlist: playlistID).count == 5)
    }

    /// `ARD.de` in the guide and `ard.de` in the playlist are one channel.
    @Test
    func `channel ids match regardless of case`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, body: guide(channel: "ARD.de", hours: 0 ..< 3))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)
        let report = try await importer(store, body: guide(channel: "ard.DE", hours: 0 ..< 3))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        #expect(report.programmes.inserted == 0)
        #expect(await store.allProgrammes(playlist: playlistID).count == 3)
    }

    // MARK: - Safety

    /// A guide cut off part-way must fail, and must not take the stored
    /// listings with it.
    @Test
    func `a truncated guide removes nothing`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, body: guide(hours: 0 ..< 40))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        let cut = String(guide(hours: 0 ..< 40).prefix(1500))
        await #expect(throws: EPGError.truncated) {
            _ = try await importer(store, body: cut).importEPG(playlist: playlistID, url: guideURL, window: wholeDay)
        }
        #expect(await store.allProgrammes(playlist: playlistID).count == 40)
    }

    @Test
    func `an empty guide does not wipe stored listings`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, body: guide(hours: 0 ..< 40))
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        let report = try await importer(store, body: "<tv></tv>")
            .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)

        #expect(report.deferredStale == 40)
        #expect(report.removedStale == 0)
        #expect(await store.allProgrammes(playlist: playlistID).count == 40)
    }

    @Test
    func `an error page is rejected`() async {
        await #expect(throws: EPGError.notXMLTV) {
            _ = try await importer(InMemoryCatalogStore(), body: "<html>Forbidden</html>")
                .importEPG(playlist: playlistID, url: guideURL, window: wholeDay)
        }
    }
}
