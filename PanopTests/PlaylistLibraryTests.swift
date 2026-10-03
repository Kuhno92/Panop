import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

private let panel = "http://panel.example:8080"

@Suite("Playlist library", .serialized)
@MainActor
struct PlaylistLibraryTests {
    // MARK: - Adding

    @Test
    func `adding an Xtream login stores it, keeps the password out of the record, and imports`() async throws {
        let app = try TestApp(transport: FakePanel(live: 5, movies: 3).transport())
        defer { app.cleanUp() }

        let playlist = try await app.services.library.add(
            .xtream(name: "Home", baseURL: panel, username: "alice", password: "s3cret")
        )
        await app.services.sync.waitForCompletion(playlist.id)

        #expect(playlist.name == "Home")
        #expect(playlist.kind == .xtream)
        #expect(playlist.displayHost == "panel.example")
        #expect(app.services.library.playlists.map(\.id) == [playlist.id])

        // The secret is in the credential store, not in the record.
        #expect(try app.credentials.load(for: playlist.id)?.password == "s3cret")
        let record = try #require(try app.storedRecords().first)
        let everything = [record.id, record.name, record.displayHost, record.kindRaw, record.localFileName ?? ""]
            .joined(separator: "|")
        #expect(!everything.contains("s3cret"))
        #expect(!everything.contains("alice"))
        #expect(!everything.contains("8080"), "the full server address must not be stored in the record")

        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: playlist.id) == 5)
        #expect(try await app.services.catalogStore.entryCount(kind: .movie, playlist: playlist.id) == 3)
        guard case let .finished(summary) = app.services.syncStatus.status(for: playlist.id) else {
            Issue.record("status was \(app.services.syncStatus.status(for: playlist.id))")
            return
        }
        #expect(summary.entries == 8)
    }

    @Test
    func `a blank name falls back to the host`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "  ",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        await app.services.sync.waitForCompletion(playlist.id)
        #expect(playlist.name == "panel.example")
    }

    /// Nothing may be left behind when a login is rejected: no record, no secret.
    @Test
    func `bad credentials are rejected before anything is stored`() async throws {
        let bad = FakePanel(loginBody: #"{"user_info":{"auth":0}}"#)
        let app = try TestApp(transport: bad.transport())
        defer { app.cleanUp() }

        let error = try await #require(throwsError { try await app.services.library.add(
            .xtream(name: "", baseURL: panel, username: "alice", password: "wrong")
        ) })

        #expect((error as? PlaylistAddError)?.message == "The provider rejected the username or password.")
        #expect(app.services.library.playlists.isEmpty)
        #expect(try app.storedRecords().isEmpty)
        #expect(app.credentials.isEmpty)
    }

    @Test
    func `an unreachable provider is reported plainly`() async throws {
        let app = try TestApp(transport: FakePanel(unreachable: true).transport())
        defer { app.cleanUp() }

        let error = try await #require(throwsError { try await app.services.library.add(
            .xtream(name: "", baseURL: panel, username: "a", password: "b")
        ) })

        let message = try #require((error as? PlaylistAddError)?.message)
        #expect(message.contains("Could not reach the provider"))
        #expect(app.services.library.playlists.isEmpty)
    }

    @Test(arguments: ["", "not a url", "ftp://host/list.m3u", "http://"])
    func `an unusable M3U link is rejected`(link: String) async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }

        await #expect(throws: PlaylistAddError.self) {
            try await app.services.library.add(.m3uURL(name: "", url: link, guideURL: nil))
        }
        #expect(app.services.library.playlists.isEmpty)
    }

    @Test
    func `an M3U link is stored as a secret, never in the record`() async throws {
        let playlistText = playlistText(live: 0 ..< 4)
        let app = try TestApp(transport: StubTransport { _ in (200, playlistText) })
        defer { app.cleanUp() }
        let link = "http://panel.example/get.php?username=alice&password=s3cret"

        let playlist = try await app.services.library.add(.m3uURL(name: "", url: link, guideURL: ""))
        await app.services.sync.waitForCompletion(playlist.id)

        #expect(playlist.kind == .remoteM3U)
        #expect(playlist.displayHost == "panel.example")
        #expect(try app.credentials.load(for: playlist.id)?.url == link)
        #expect(try app.credentials.load(for: playlist.id)?.guideURL == nil, "an empty guide field must not be stored")
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: playlist.id) == 4)
    }

    @Test
    func `a local file is copied into the app and imported from the copy`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        let original = try writeTemporaryFile(playlistText(live: 0 ..< 6))

        let playlist = try await app.services.library.add(.m3uFile(
            name: "Mine",
            fileURL: URL(fileURLWithPath: original)
        ))
        await app.services.sync.waitForCompletion(playlist.id)

        // Removing the original must not break refreshing.
        try FileManager.default.removeItem(atPath: original)
        #expect(FileManager.default.fileExists(atPath: app.directory.appendingPathComponent("\(playlist.id).m3u").path))
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: playlist.id) == 6)
        #expect(try app.services.library.descriptor(for: playlist.id)?.source.isLocal == true)
    }

    @Test
    func `an unreadable file is rejected`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        await #expect(throws: PlaylistAddError.self) {
            try await app.services.library.add(.m3uFile(name: "", fileURL: URL(fileURLWithPath: "/nonexistent/x.m3u")))
        }
        #expect(app.services.library.playlists.isEmpty)
    }

    // MARK: - Using

    @Test
    func `a stored playlist turns back into an importable descriptor`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "",
            baseURL: panel,
            username: "alice",
            password: "s3cret"
        ))
        await app.services.sync.waitForCompletion(playlist.id)

        let descriptor = try #require(try app.services.library.descriptor(for: playlist.id))

        #expect(descriptor.id == playlist.id)
        #expect(descriptor.source == .xtream(ProviderCredentials(
            baseURL: panel,
            username: "alice",
            password: "s3cret"
        )))
    }

    /// A record can exist without its secret, for example after syncing to a
    /// device that never had the Keychain entry. That must not crash or guess.
    @Test
    func `a playlist whose secret is missing has no descriptor`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        await app.services.sync.waitForCompletion(playlist.id)

        try app.credentials.delete(for: playlist.id)

        #expect(try app.services.library.descriptor(for: playlist.id) == nil)
        #expect(try app.services.library.descriptor(for: "unknown") == nil)
    }

    @Test
    func `playlists keep the order they were added in`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        var ids: [String] = []
        for name in ["One", "Two", "Three"] {
            let playlist = try await app.services.library.add(.xtream(
                name: name,
                baseURL: panel,
                username: "a",
                password: "b"
            ))
            await app.services.sync.waitForCompletion(playlist.id)
            ids.append(playlist.id)
        }
        #expect(app.services.library.playlists.map(\.id) == ids)
        #expect(app.services.library.playlists.map(\.name) == ["One", "Two", "Three"])
    }

    // MARK: - Removing

    @Test
    func `removing a playlist deletes its rows, secret, file and record`() async throws {
        let app = try TestApp(transport: FakePanel(live: 4).transport())
        defer { app.cleanUp() }
        let library = app.services.library
        let xtream = try await library.add(.xtream(name: "X", baseURL: panel, username: "a", password: "b"))
        let original = try writeTemporaryFile(playlistText(live: 0 ..< 3))
        let local = try await library.add(.m3uFile(name: "L", fileURL: URL(fileURLWithPath: original)))
        for id in [xtream.id, local.id] {
            await app.services.sync.waitForCompletion(id)
        }

        await library.remove(local.id)

        #expect(library.playlists.map(\.id) == [xtream.id])
        #expect(try app.credentials.load(for: local.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: app.directory.appendingPathComponent("\(local.id).m3u").path))
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: local.id) == 0)
        // The other playlist is untouched.
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: xtream.id) == 4)
        #expect(try app.credentials.load(for: xtream.id) != nil)
        #expect(app.services.syncStatus.status(for: local.id) == .idle)
    }

    // MARK: - Refreshing

    @Test
    func `refreshing only touches playlists that are stale`() async throws {
        let app = try TestApp(transport: FakePanel(live: 3).transport())
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        await app.services.sync.waitForCompletion(playlist.id)
        let firstFinish = try #require(finishedAt(app, playlist.id))

        // Fresh: within the maximum age, so nothing starts.
        await app.services.library.refreshStale(maxAge: 3600)
        await app.services.sync.waitForCompletion(playlist.id)
        #expect(finishedAt(app, playlist.id) == firstFinish)

        // Stale: a maximum age of zero refreshes it.
        try await Task.sleep(for: .milliseconds(20))
        await app.services.library.refreshStale(maxAge: 0)
        await app.services.sync.waitForCompletion(playlist.id)
        #expect(try #require(finishedAt(app, playlist.id)) > firstFinish)
    }

    // MARK: - Refreshing, stopping and deleting

    /// A refresh that cannot run must say so. Doing nothing looks like a broken button.
    @Test
    func `refreshing a playlist whose login is missing says so on its row`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        await app.services.sync.waitForCompletion(playlist.id)
        try app.credentials.delete(for: playlist.id)

        await app.services.library.refresh(playlist.id)

        guard case let .failed(message) = app.services.syncStatus.status(for: playlist.id) else {
            Issue.record("expected a failed status, got \(app.services.syncStatus.status(for: playlist.id))")
            return
        }
        #expect(message.contains("login details are missing"))
    }

    @Test
    func `refresh all updates every playlist`() async throws {
        let app = try TestApp(transport: FakePanel(live: 3).transport())
        defer { app.cleanUp() }
        var ids: [String] = []
        for name in ["One", "Two"] {
            let playlist = try await app.services.library.add(.xtream(
                name: name,
                baseURL: panel,
                username: "a",
                password: "b"
            ))
            await app.services.sync.waitForCompletion(playlist.id)
            ids.append(playlist.id)
        }
        let before = ids.compactMap { finishedAt(app, $0) }
        try await Task.sleep(for: .milliseconds(20))

        await app.services.library.refreshAll()
        for id in ids {
            await app.services.sync.waitForCompletion(id)
        }

        let after = ids.compactMap { finishedAt(app, $0) }
        #expect(before.count == 2 && after.count == 2)
        #expect(zip(before, after).allSatisfy { $0 < $1 }, "not every playlist was refreshed")
    }

    /// Stopping is the user's choice. It must not read as a failure.
    @Test
    func `stopping a sync leaves the playlist idle, not failed`() async throws {
        let transport = SwitchableTransport(FakePanel().transport())
        let app = try TestApp(transport: transport)
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        await app.services.sync.waitForCompletion(playlist.id)

        transport.setHanging(true)
        await app.services.library.refresh(playlist.id)
        #expect(await waitFor { app.services.syncStatus.status(for: playlist.id) == .syncing(processed: 0) })

        await app.services.library.stop(playlist.id)
        await app.services.sync.waitForCompletion(playlist.id)

        #expect(app.services.syncStatus.status(for: playlist.id) == .idle)
    }

    /// Delete has to work on a playlist that is busy: that is when a user reaches for it.
    @Test
    func `a playlist can be deleted while it is still syncing`() async throws {
        let transport = SwitchableTransport(FakePanel(live: 5).transport())
        let app = try TestApp(transport: transport)
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        await app.services.sync.waitForCompletion(playlist.id)
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: playlist.id) == 5)

        transport.setHanging(true)
        await app.services.library.refresh(playlist.id, force: true)
        #expect(await waitFor { app.services.syncStatus.status(for: playlist.id) == .syncing(processed: 0) })

        let problem = await app.services.library.remove(playlist.id)

        #expect(problem == nil)
        #expect(app.services.library.playlists.isEmpty)
        #expect(app.services.library.removing.isEmpty)
        #expect(try app.storedRecords().isEmpty)
        #expect(app.credentials.isEmpty)
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: playlist.id) == 0)
    }

    @Test
    func `deleting the same playlist twice is harmless`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        await app.services.sync.waitForCompletion(playlist.id)

        async let first = app.services.library.remove(playlist.id)
        async let second = app.services.library.remove(playlist.id)
        let results = await [first, second]

        #expect(results.allSatisfy { $0 == nil })
        #expect(app.services.library.playlists.isEmpty)
    }

    @Test
    func `a playlist that never synced can be deleted`() async throws {
        let transport = SwitchableTransport(FakePanel().transport())
        let app = try TestApp(transport: transport)
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(.xtream(
            name: "",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        await app.services.sync.waitForCompletion(playlist.id)
        try await app.services.catalogStore.removePlaylist(playlist.id)

        #expect(await app.services.library.remove(playlist.id) == nil)
        #expect(app.services.library.playlists.isEmpty)
    }

    // MARK: - Skipped entries

    @Test
    func `entries with no playable address are counted on the summary, not silently dropped`() async throws {
        let app = try TestApp(transport: StubTransport { _ in (404, "") })
        defer { app.cleanUp() }
        // A file has no address to resolve a relative path against, so these two are unusable.
        let text = "#EXTM3U\n#EXTINF:-1,Relative\n/live/1.ts\n#EXTINF:-1,Also relative\nlive/2.ts\n#EXTINF:-1,Good\nhttp://h/3.ts\n"
        let file = try writeTemporaryFile(text)

        let playlist = try await app.services.library.add(.m3uFile(name: "Mixed", fileURL: URL(fileURLWithPath: file)))
        await app.services.sync.waitForCompletion(playlist.id)

        guard case let .finished(summary) = app.services.syncStatus.status(for: playlist.id) else {
            Issue.record("the import did not finish")
            return
        }
        #expect(summary.entries == 1)
        #expect(summary.skipped == 2)
    }

    @Test
    func `a clean playlist skips nothing`() async throws {
        let app = try TestApp(transport: StubTransport { _ in (404, "") })
        defer { app.cleanUp() }
        let file = try writeTemporaryFile(playlistText(live: 0 ..< 4))

        let playlist = try await app.services.library.add(.m3uFile(name: "Clean", fileURL: URL(fileURLWithPath: file)))
        await app.services.sync.waitForCompletion(playlist.id)

        guard case let .finished(summary) = app.services.syncStatus.status(for: playlist.id) else {
            Issue.record("the import did not finish")
            return
        }
        #expect(summary.skipped == 0)
    }

    // MARK: - Helpers

    private func waitFor(_ condition: () -> Bool, seconds: Double = 5) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func finishedAt(_ app: TestApp, _ id: String) -> Date? {
        if case let .finished(summary) = app.services.syncStatus.status(for: id) {
            summary.finishedAt
        } else {
            nil
        }
    }

    private func throwsError(_ body: () async throws -> some Any) async -> (any Error)? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }
}

private extension PlaylistSource {
    var isLocal: Bool {
        if case .localM3U = self {
            true
        } else {
            false
        }
    }
}

/// What happens when another device changes the playlists and the change arrives.
@Suite("Playlists changed on another device", .serialized)
@MainActor
struct RemotePlaylistChangeTests {
    private func addPlaylist(_ app: TestApp) async throws -> PlaylistSummary {
        let playlist = try await app.services.library.add(
            .xtream(name: "Home", baseURL: panel, username: "alice", password: "s3cret")
        )
        await app.services.sync.waitForCompletion(playlist.id)
        return playlist
    }

    @Test
    func `a playlist removed elsewhere is removed here, with its channels, its login and what hangs off it`(
    ) async throws {
        let app = try TestApp(transport: FakePanel(live: 4, movies: 2).transport())
        defer { app.cleanUp() }
        let playlist = try await addPlaylist(app)
        var removed: [String] = []
        app.services.library.onRemoved = { removed.append($0) }

        // The other device deleted it: the record is gone from the synced store.
        let other = ModelContext(app.cloud)
        for record in try other.fetch(FetchDescriptor<PlaylistRecord>()) {
            other.delete(record)
        }
        try other.save()
        await app.services.library.applyRemoteChanges()

        #expect(app.services.library.playlists.isEmpty)
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: playlist.id) == 0)
        #expect(try app.credentials.load(for: playlist.id) == nil)
        #expect(removed == [playlist.id])
    }

    @Test
    func `nothing changes when nothing was removed elsewhere`() async throws {
        let app = try TestApp(transport: FakePanel(live: 4, movies: 2).transport())
        defer { app.cleanUp() }
        let playlist = try await addPlaylist(app)
        var removed: [String] = []
        app.services.library.onRemoved = { removed.append($0) }

        await app.services.library.applyRemoteChanges()

        #expect(app.services.library.playlists.map(\.id) == [playlist.id])
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: playlist.id) == 4)
        #expect(removed.isEmpty)
    }

    @Test
    func `a playlist that arrives with its login is listed and fetched`() async throws {
        let app = try TestApp(transport: FakePanel(live: 3, movies: 1).transport())
        defer { app.cleanUp() }
        // What the other device made: a record, and (as the login travels with it) the secret here too.
        let other = ModelContext(app.cloud)
        other.insert(PlaylistRecord(
            id: "from-elsewhere",
            name: "Elsewhere",
            kind: .xtream,
            displayHost: "panel.example"
        ))
        try other.save()
        try app.credentials.save(
            PlaylistSecret(url: panel, username: "alice", password: "s3cret", guideURL: nil), for: "from-elsewhere"
        )

        await app.services.library.applyRemoteChanges()
        await app.services.sync.waitForCompletion("from-elsewhere")

        #expect(app.services.library.playlists.map(\.id) == ["from-elsewhere"])
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: "from-elsewhere") == 3)
    }

    @Test
    func `a playlist that arrives without its login is listed and not fetched, rather than failing`() async throws {
        let app = try TestApp(transport: FakePanel(live: 3, movies: 1).transport())
        defer { app.cleanUp() }
        let other = ModelContext(app.cloud)
        other.insert(PlaylistRecord(id: "no-login", name: "No login", kind: .xtream, displayHost: "panel.example"))
        try other.save()

        await app.services.library.applyRemoteChanges()

        #expect(app.services.library.playlists.map(\.id) == ["no-login"])
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: "no-login") == 0)
    }
}
