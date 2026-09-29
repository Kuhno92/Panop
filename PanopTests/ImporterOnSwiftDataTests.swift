import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import Testing

private let playlist = "e2e"

private func importer(_ catalog: OnDiskCatalog, batchSize: Int = 100) -> CatalogImporter {
    CatalogImporter(
        store: catalog.store,
        transport: StubTransport { _ in (404, "") },
        batchSize: batchSize
    )
}

/// The importer's guarantees, proven against the real store rather than the
/// in-memory one the package tests use.
@Suite("Importer on SwiftData")
struct ImporterOnSwiftDataTests {
    @Test
    func `imports a playlist end to end`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }

        let path = try writeTemporaryFile(playlistText(live: 0 ..< 250, movies: 0 ..< 40))
        let report = try await importer(catalog).importM3U(playlist: playlist, source: .file(path: path))

        #expect(report.kinds.first { $0.kind == .live }?.summary.inserted == 250)
        #expect(report.kinds.first { $0.kind == .movie }?.summary.inserted == 40)
        #expect(try await catalog.store.entryCount(kind: .live, playlist: playlist) == 250)
        #expect(try await catalog.store.categoryIDs(kind: .live, playlist: playlist) == ["News"])
    }

    /// The property that makes a routine refresh cheap, on the real store.
    @Test
    func `a forced re-import of the same playlist changes nothing`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let path = try writeTemporaryFile(playlistText(live: 0 ..< 300))
        let sut = importer(catalog)
        _ = try await sut.importM3U(playlist: playlist, source: .file(path: path))

        let report = try await sut.importM3U(playlist: playlist, source: .file(path: path), force: true)

        let live = try #require(report.kinds.first { $0.kind == .live })
        #expect(live.summary.unchanged == 300)
        #expect(live.summary.inserted == 0)
        #expect(live.summary.updated == 0)
        #expect(live.removed == 0)
    }

    @Test
    func `a small removal is swept and a large drop is held back`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let sut = importer(catalog)
        _ = try await sut.importM3U(
            playlist: playlist,
            source: .file(path: writeTemporaryFile(playlistText(live: 0 ..< 200)))
        )

        let small = try await sut.importM3U(
            playlist: playlist,
            source: .file(path: writeTemporaryFile(playlistText(live: 0 ..< 190)))
        )
        #expect(small.kinds.first?.removed == 10)
        #expect(try await catalog.store.entryCount(kind: .live, playlist: playlist) == 190)

        // A cut-off download: a fifth of the file.
        let truncated = try await sut.importM3U(
            playlist: playlist,
            source: .file(path: writeTemporaryFile(playlistText(live: 0 ..< 38)))
        )
        #expect(truncated.kinds.first?.removed == 0)
        #expect(truncated.deferredRemovals.first?.ids.count == 152)
        #expect(try await catalog.store.entryCount(kind: .live, playlist: playlist) == 190)
    }

    @Test
    func `a held back removal can be confirmed`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let sut = importer(catalog)
        _ = try await sut.importM3U(
            playlist: playlist,
            source: .file(path: writeTemporaryFile(playlistText(live: 0 ..< 200)))
        )
        let held = try await sut.importM3U(
            playlist: playlist,
            source: .file(path: writeTemporaryFile(playlistText(live: 0 ..< 40)))
        )

        try await sut.confirm(#require(held.deferredRemovals.first), playlist: playlist)

        #expect(try await catalog.store.entryCount(kind: .live, playlist: playlist) == 40)
    }

    @Test
    func `a guide imports, refreshes and expires`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let day = Date(timeIntervalSince1970: 1_790_640_000)
        let window = day ... day.addingTimeInterval(48 * 3600)

        func guide(hours: Range<Int>) -> String {
            var lines = [#"<tv><channel id="ard.de"><display-name>ARD</display-name></channel>"#]
            for hour in hours {
                let start = String(format: "202609%02d%02d0000 +0000", 29 + hour / 24, hour % 24)
                let stop = String(format: "202609%02d%02d0000 +0000", 29 + (hour + 1) / 24, (hour + 1) % 24)
                lines
                    .append(
                        #"<programme start="\#(start)" stop="\#(stop)" channel="ard.de"><title>Show \#(hour)</title></programme>"#
                    )
            }
            return lines.joined(separator: "\n") + "\n</tv>"
        }
        func run(_ body: String, window: ClosedRange<Date>) async throws -> EPGImportReport {
            let sut = CatalogImporter(
                store: catalog.store,
                transport: StubTransport { _ in (200, body) },
                batchSize: 7
            )
            let url = try #require(URL(string: "http://panel.example/xmltv.php"))
            return try await sut.importEPG(playlist: playlist, url: url, window: window)
        }

        let first = try await run(guide(hours: 0 ..< 20), window: window)
        #expect(first.programmes.inserted == 20)

        let again = try await run(guide(hours: 0 ..< 20), window: window)
        #expect(again.programmes.unchanged == 20)

        // Six hours later: the first six are history, two rescheduled away.
        let later = day.addingTimeInterval(6 * 3600) ... day.addingTimeInterval(54 * 3600)
        let refreshed = try await run(guide(hours: 6 ..< 18), window: later)
        #expect(refreshed.removedExpired == 6)
        #expect(refreshed.removedStale == 2)
        #expect(try await catalog.store.programmeCount(playlist: playlist, endingAfter: later.lowerBound) == 12)
    }
}
