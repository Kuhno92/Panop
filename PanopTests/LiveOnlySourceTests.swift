import Foundation
@testable import Panop
import PanopCatalog
import Testing

private let panel = "http://panel.example:8080"

@Suite("Live-only sources", .serialized)
@MainActor
struct LiveOnlySourceTests {
    @Test
    func `a live-only source imports its channels and none of its movies`() async throws {
        let app = try TestApp(transport: FakePanel(live: 5, movies: 3).transport())
        defer { app.cleanUp() }

        let playlist = try await app.services.library.add(
            .xtream(name: "Live", baseURL: panel, username: "alice", password: "pw"),
            includeVOD: false
        )
        await app.services.sync.waitForCompletion(playlist.id)

        #expect(!playlist.includesVOD)
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: playlist.id) == 5)
        #expect(try await app.services.catalogStore.entryCount(kind: .movie, playlist: playlist.id) == 0)
        #expect(try app.services.library.descriptor(for: playlist.id)?.includeVOD == false)
    }

    @Test
    func `movies and series are offered unless every source is live-only`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        let library = app.services.library
        #expect(library.offersVOD, "with no source yet there is nothing to hide")

        let live = try await library.add(
            .xtream(name: "Live", baseURL: panel, username: "a", password: "b"),
            includeVOD: false
        )
        #expect(!library.offersVOD)

        let full = try await library.add(.xtream(name: "Full", baseURL: panel, username: "a", password: "b"))
        #expect(library.offersVOD)

        _ = await library.remove(full.id)
        #expect(!library.offersVOD, "and they go again when the last source with them is deleted")
        await app.services.sync.waitForCompletion(live.id)
    }

    @Test
    func `turning movies off removes them, and turning them on brings them back`() async throws {
        let app = try TestApp(transport: FakePanel(live: 5, movies: 3).transport())
        defer { app.cleanUp() }
        let library = app.services.library
        let store = app.services.catalogStore
        let playlist = try await library.add(.xtream(name: "P", baseURL: panel, username: "a", password: "b"))
        await app.services.sync.waitForCompletion(playlist.id)
        #expect(try await store.entryCount(kind: .movie, playlist: playlist.id) == 3)

        #expect(await library.setIncludesVOD(false, for: playlist.id) == nil)
        #expect(try await store.entryCount(kind: .movie, playlist: playlist.id) == 0)
        #expect(try await store.entryCount(kind: .live, playlist: playlist.id) == 5, "channels stay")
        #expect(!library.offersVOD)

        #expect(await library.setIncludesVOD(true, for: playlist.id) == nil)
        await app.services.sync.waitForCompletion(playlist.id)
        #expect(try await store.entryCount(kind: .movie, playlist: playlist.id) == 3)
        #expect(library.offersVOD)
    }
}
