import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

private let playlistID = "p1"

private func importer(
    _ store: any CatalogStore,
    batchSize: Int = 1000,
    transport: StubTransport = StubTransport { _ in (404, "") }
) -> CatalogImporter {
    CatalogImporter(store: store, transport: transport, batchSize: batchSize)
}

@Suite("M3U import")
struct M3UImportTests {
    // MARK: - Basics

    @Test
    func `imports entries, categories and guide URLs`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile(livePlaylist(0 ..< 3, group: "News", epgURL: "http://epg/guide.xml.gz"))

        let report = try await importer(store).importM3U(playlist: playlistID, source: .file(path: path))

        #expect(report.outcome == .imported)
        #expect(report.epgURLs == ["http://epg/guide.xml.gz"])
        let live = try #require(report.kinds.first { $0.kind == .live })
        #expect(live.imported == 3)
        #expect(live.summary.inserted == 3)

        let entries = await store.allEntries(playlist: playlistID)
        #expect(entries.count == 3)
        let first = try #require(entries.first { $0.name == "Channel 0" })
        #expect(first.kind == .live)
        #expect(first.groupName == "News")
        #expect(first.epgKey == "chan.0")
        #expect(first.iconURL == "http://img/0.png")
        #expect(first.streamURL == "http://host/live/u/p/0.ts")
        #expect(await store.allCategories(playlist: playlistID) == [CatalogCategory(
            id: "News",
            kind: .live,
            name: "News"
        )])
    }

    @Test
    func `entries without a URL are skipped`() async throws {
        let store = InMemoryCatalogStore()
        let path = try writeTemporaryFile("#EXTM3U\n#EXTINF:-1,No url\n#EXTINF:-1,Has url\nhttp://host/live/u/p/1.ts\n")
        _ = try await importer(store).importM3U(playlist: playlistID, source: .file(path: path))
        #expect(await store.allEntries(playlist: playlistID).map(\.name) == ["Has url"])
    }

    /// M3U files repeat stream URLs. They are one row, not a crash or two rows.
    @Test
    func `a repeated URL is one entry`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="A",First
        http://host/live/u/p/1.ts
        #EXTINF:-1 group-title="B",Second
        http://host/live/u/p/1.ts
        """
        _ = try await importer(store).importM3U(playlist: playlistID, source: .file(path: writeTemporaryFile(text)))
        #expect(await store.allEntries(playlist: playlistID).count == 1)
    }

    // MARK: - Identity

    /// Favourites and watch progress are keyed by the id. A provider that
    /// regroups its channels must not orphan them.
    @Test
    func `regrouping keeps the same identity`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store)
        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 5, group: "News")))
        )
        let before = await store.allEntries(playlist: playlistID).map(\.id)

        let report = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 5, group: "Sport")))
        )

        #expect(await store.allEntries(playlist: playlistID).map(\.id) == before)
        let live = try #require(report.kinds.first { $0.kind == .live })
        #expect(live.summary.updated == 5)
        #expect(live.summary.inserted == 0)
    }

    // MARK: - Skipping unchanged work

    @Test
    func `an unchanged file is skipped entirely`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store)
        let path = try writeTemporaryFile(livePlaylist(0 ..< 20))

        _ = try await sut.importM3U(playlist: playlistID, source: .file(path: path))
        let writes = await store.writeCount
        let counter = try #require(await store.syncState(playlist: playlistID)).importCounter

        let report = try await sut.importM3U(playlist: playlistID, source: .file(path: path))

        #expect(report.outcome == .unchanged)
        #expect(await store.writeCount == writes)
        #expect(try #require(await store.syncState(playlist: playlistID)).importCounter == counter)
    }

    /// Forcing re-reads the file, but rows that did not change must not be
    /// written again: that is what keeps a routine refresh cheap.
    @Test
    func `a forced re-import of the same content writes nothing`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store)
        let path = try writeTemporaryFile(livePlaylist(0 ..< 50))

        _ = try await sut.importM3U(playlist: playlistID, source: .file(path: path))
        let writes = await store.writeCount

        let report = try await sut.importM3U(playlist: playlistID, source: .file(path: path), force: true)

        let live = try #require(report.kinds.first { $0.kind == .live })
        #expect(live.summary.unchanged == 50)
        #expect(live.summary.inserted == 0)
        #expect(live.summary.updated == 0)
        #expect(await store.writeCount == writes)
    }

    @Test
    func `state records the digest and completion`() async throws {
        let store = InMemoryCatalogStore()
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let sut = CatalogImporter(store: store, transport: StubTransport { _ in (404, "") }, now: { fixedNow })
        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 2)))
        )

        let state = try #require(await store.syncState(playlist: playlistID))
        #expect(state.importCounter == 1)
        #expect(state.digest != nil)
        #expect(state.lastCompleted == fixedNow)
    }

    // MARK: - Removal and its safety

    @Test
    func `a small removal is carried out`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store)
        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 10)))
        )

        let report = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 6)))
        )

        let live = try #require(report.kinds.first { $0.kind == .live })
        #expect(live.removed == 4)
        #expect(await store.allEntries(playlist: playlistID).count == 6)
    }

    /// The whole reason for the safety rule: a download cut off at a fifth of
    /// the file is a valid, shorter playlist as far as the parser can tell.
    @Test
    func `a large drop is held back instead of deleting`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store)
        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 200)))
        )

        let report = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 40)))
        )

        let live = try #require(report.kinds.first { $0.kind == .live })
        #expect(live.removed == 0)
        #expect(live.deferredRemoval?.ids.count == 160)
        #expect(await store.allEntries(playlist: playlistID).count == 200)
    }

    @Test
    func `an empty playlist never wipes a full catalog`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store)
        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 100)))
        )

        let report = try await sut.importM3U(playlist: playlistID, source: .file(path: writeTemporaryFile("#EXTM3U\n")))

        #expect(report.deferredRemovals.first?.ids.count == 100)
        #expect(await store.allEntries(playlist: playlistID).count == 100)
    }

    @Test
    func `a held back removal can be confirmed`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store)
        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 200)))
        )
        let report = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 40)))
        )
        let removal = try #require(report.deferredRemovals.first)

        try await sut.confirm(removal, playlist: playlistID)

        #expect(await store.allEntries(playlist: playlistID).count == 40)
    }

    /// A newer import may have brought the rows back, so an old confirmation
    /// must not delete them.
    @Test
    func `a confirmation after a newer import is refused`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store)
        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 200)))
        )
        let truncated = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 40)))
        )
        let removal = try #require(truncated.deferredRemovals.first)

        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 200)))
        )

        await #expect(throws: CatalogError.staleConfirmation) {
            try await sut.confirm(removal, playlist: playlistID)
        }
        #expect(await store.allEntries(playlist: playlistID).count == 200)
    }

    @Test
    func `the gate is configurable`() async throws {
        let store = InMemoryCatalogStore()
        let strict = CatalogImporter(
            store: store,
            transport: StubTransport { _ in (404, "") },
            policy: PrunePolicy(maxRemovedFraction: 0.1, alwaysAllowUpTo: 0)
        )
        _ = try await strict.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 100)))
        )
        let report = try await strict.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 80)))
        )
        #expect(report.deferredRemovals.first?.ids.count == 20)
    }

    // MARK: - Failure

    /// A store error part-way through must leave every existing row alone, and
    /// must not record the import as completed.
    @Test
    func `a failure mid-import removes nothing`() async throws {
        // Upserts 1 and 2 seed the catalog; the third lets one batch of the
        // second import through; the fourth fails.
        let store = FlakyStore(failFromUpsert: 4)
        let sut = CatalogImporter(store: store, transport: StubTransport { _ in (404, "") }, batchSize: 10)

        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 15)))
        )
        let original = await store.base.allEntries(playlist: playlistID).map(\.id)
        let completed = try #require(await store.base.syncState(playlist: playlistID)).lastCompleted

        await #expect(throws: FlakyStore.Failure.self) {
            _ = try await sut.importM3U(
                playlist: playlistID,
                source: .file(path: writeTemporaryFile(livePlaylist(100 ..< 160)))
            )
        }

        let after = await Set(store.base.allEntries(playlist: playlistID).map(\.id))
        #expect(Set(original).isSubset(of: after), "an existing row was removed")
        #expect(try #require(await store.base.syncState(playlist: playlistID)).lastCompleted == completed)
    }

    @Test
    func `a missing file is reported`() async {
        await #expect(throws: CatalogError.cannotReadFile) {
            _ = try await importer(InMemoryCatalogStore()).importM3U(
                playlist: playlistID,
                source: .file(path: "/nonexistent/panop.m3u")
            )
        }
    }

    // MARK: - Remote

    @Test
    func `downloads and imports a remote playlist`() async throws {
        let store = InMemoryCatalogStore()
        let body = livePlaylist(0 ..< 30)
        let transport = StubTransport(chunkSize: 100) { _ in (200, body) }
        let directory = try makeWorkingDirectory()
        let sut = CatalogImporter(store: store, transport: transport, workingDirectory: directory)
        let url = try #require(URL(string: "http://panel.example/get.php?username=alice&password=s3cret"))

        let report = try await sut.importM3U(playlist: playlistID, source: .remote(url))

        #expect(report.kinds.first?.imported == 30)
        #expect(await store.allEntries(playlist: playlistID).count == 30)
        #expect(fileCount(in: directory) == 0, "the downloaded file must not be left behind")
    }

    @Test
    func `a remote playlist that has not changed is skipped`() async throws {
        let store = InMemoryCatalogStore()
        let body = livePlaylist(0 ..< 30)
        let sut = CatalogImporter(store: store, transport: StubTransport { _ in (200, body) })
        let url = try #require(URL(string: "http://panel.example/list.m3u"))

        _ = try await sut.importM3U(playlist: playlistID, source: .remote(url))
        let second = try await sut.importM3U(playlist: playlistID, source: .remote(url))

        #expect(second.outcome == .unchanged)
    }

    @Test
    func `an HTTP error is reported and changes nothing`() async throws {
        let store = InMemoryCatalogStore()
        let directory = try makeWorkingDirectory()
        let sut = CatalogImporter(
            store: store,
            transport: StubTransport { _ in (403, "") },
            workingDirectory: directory
        )
        let url = try #require(URL(string: "http://panel.example/list.m3u"))

        await #expect(throws: CatalogError.http(status: 403)) {
            _ = try await sut.importM3U(playlist: playlistID, source: .remote(url))
        }
        #expect(await store.syncState(playlist: playlistID) == nil)
        #expect(fileCount(in: directory) == 0)
    }

    @Test
    func `download errors are scrubbed of credentials`() async throws {
        let transport = StubTransport { request in
            throw NSError(
                domain: "test",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "failed: \(request.url.absoluteString)"]
            )
        }
        let sut = CatalogImporter(store: InMemoryCatalogStore(), transport: transport)
        let url = try #require(URL(string: "http://panel.example/get.php?username=alice&password=s3cret"))

        do {
            _ = try await sut.importM3U(playlist: playlistID, source: .remote(url, redacting: ["alice", "s3cret"]))
            Issue.record("expected a throw")
        } catch let CatalogError.download(message) {
            #expect(!message.contains("s3cret"))
            #expect(!message.contains("alice"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Progress and batching

    @Test
    func `reports progress per batch`() async throws {
        let collected = ProgressLog()
        let sut = CatalogImporter(
            store: InMemoryCatalogStore(),
            transport: StubTransport { _ in (404, "") },
            batchSize: 100,
            progress: { collected.append($0.processed) }
        )
        _ = try await sut.importM3U(
            playlist: playlistID,
            source: .file(path: writeTemporaryFile(livePlaylist(0 ..< 350)))
        )

        let values = collected.values
        #expect(values == values.sorted())
        #expect(values.last == 350)
        #expect(values.count >= 3)
    }

    @Test
    func `batch size does not change the result`() async throws {
        let text = livePlaylist(0 ..< 137)
        var results: [[CatalogEntry]] = []
        for size in [1, 7, 50, 1000] {
            let store = InMemoryCatalogStore()
            _ = try await importer(store, batchSize: size).importM3U(
                playlist: playlistID,
                source: .file(path: writeTemporaryFile(text))
            )
            await results.append(store.allEntries(playlist: playlistID))
        }
        #expect(results.dropFirst().allSatisfy { $0 == results[0] })
    }
}

/// An empty directory of its own, so a leak check cannot be fooled by other
/// tests running in parallel.
private func makeWorkingDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("panop-work-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func fileCount(in directory: URL) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? -1
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int] = []

    func append(_ value: Int) {
        lock.withLock { stored.append(value) }
    }

    var values: [Int] {
        lock.withLock { stored }
    }
}
