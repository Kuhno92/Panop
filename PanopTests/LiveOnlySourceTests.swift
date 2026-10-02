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
}
