import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

private let panel = "http://panel.example:8080"

@Suite("Playlists arriving on a new device", .serialized)
@MainActor
struct PlaylistOfferTests {
    private func arrive(in app: TestApp) throws {
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
    }

    @Test
    func `on a device with none, what arrives is offered and not fetched until accepted`() async throws {
        let app = try TestApp(transport: FakePanel(live: 3, movies: 1).transport(), offerDecided: false)
        defer { app.cleanUp() }
        try arrive(in: app)

        await app.services.library.applyRemoteChanges()

        #expect(app.services.library.pendingOffer == ["Elsewhere"])
        #expect(app.services.library.playlists.map(\.id) == ["from-elsewhere"], "listed, so nothing is lost")
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: "from-elsewhere") == 0)

        await app.services.library.acceptOffer()
        await app.services.sync.waitForCompletion("from-elsewhere")

        #expect(app.services.library.pendingOffer == nil)
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: "from-elsewhere") == 3)
    }

    @Test
    func `the question is asked once`() async throws {
        let app = try TestApp(transport: FakePanel(live: 3, movies: 1).transport(), offerDecided: false)
        defer { app.cleanUp() }
        try arrive(in: app)
        await app.services.library.applyRemoteChanges()
        await app.services.library.acceptOffer()
        await app.services.sync.waitForCompletion("from-elsewhere")

        let other = ModelContext(app.cloud)
        other.insert(PlaylistRecord(id: "second", name: "Second", kind: .xtream, displayHost: "panel.example"))
        try other.save()
        await app.services.library.applyRemoteChanges()

        #expect(app.services.library.pendingOffer == nil, "a device that has answered is not asked again")
    }

    @Test
    func `adding a playlist of one's own answers the offer`() async throws {
        let app = try TestApp(transport: FakePanel(live: 3, movies: 1).transport(), offerDecided: false)
        defer { app.cleanUp() }
        try arrive(in: app)
        await app.services.library.applyRemoteChanges()
        #expect(app.services.library.pendingOffer != nil)

        let own = try await app.services.library.add(
            .xtream(name: "Mine", baseURL: panel, username: "alice", password: "s3cret")
        )
        await app.services.sync.waitForCompletion(own.id)

        #expect(app.services.library.pendingOffer == nil)
    }

    @Test
    func `what each state of iCloud leads to on an empty device`() {
        typealias Phase = SyncWelcomePhase
        #expect(Phase.phase(availability: .active, offer: nil, waited: false) == .searching)
        #expect(Phase.phase(availability: .active, offer: nil, waited: true) == .nothingFound)
        #expect(Phase.phase(availability: .active, offer: ["A"], waited: true) == .offer(names: ["A"]))
        #expect(Phase.phase(availability: .noAccount, offer: nil, waited: false) == .unavailable(.noAccount))
        #expect(Phase.phase(availability: .notEntitled, offer: nil, waited: true) == .unavailable(.notEntitled))
        #expect(Phase.phase(availability: .off, offer: nil, waited: false) == .plain)
        #expect(Phase.phase(availability: .testing, offer: nil, waited: false) == .plain)
    }
}
