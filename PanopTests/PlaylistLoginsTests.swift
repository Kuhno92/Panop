import Foundation
@testable import Panop
import PanopCatalog
import SwiftData
import Testing

private let panel = "http://panel.example:8080"
private let sample = PlaylistSecret(
    url: "http://panel.example:8080",
    username: "alice",
    password: "s3cret",
    guideURL: nil
)
private let changed = PlaylistSecret(
    url: "http://panel.example:8080",
    username: "alice",
    password: "new",
    guideURL: nil
)

@Suite("Playlist logins, the decision")
struct PlaylistLoginsDecisionTests {
    private var blob: Data {
        PlaylistLogins.encode(sample) ?? Data()
    }

    private var changedBlob: Data {
        PlaylistLogins.encode(changed) ?? Data()
    }

    @Test
    func `a login this device has and the record lacks is sent`() {
        #expect(PlaylistLogins.decide(local: sample, blob: nil, remembered: nil, uploading: true) == .upload(blob))
    }

    @Test
    func `a login that arrived on a device with none is taken`() {
        #expect(PlaylistLogins.decide(local: nil, blob: blob, remembered: nil, uploading: true) == .adopt(sample))
    }

    @Test
    func `the same login on both is left alone`() {
        #expect(PlaylistLogins.decide(local: sample, blob: blob, remembered: nil, uploading: true) == .none)
    }

    @Test
    func `nothing anywhere is nothing to do`() {
        #expect(PlaylistLogins.decide(local: nil, blob: nil, remembered: nil, uploading: true) == .none)
    }

    @Test
    func `when the login was changed here, the record still being what this device put there, the change is sent`() {
        let remembered = PlaylistLogins.digest(blob)
        #expect(
            PlaylistLogins.decide(local: changed, blob: blob, remembered: remembered, uploading: true)
                == .upload(changedBlob)
        )
    }

    @Test
    func `when the record changed on another device since, that one stands`() {
        let remembered = PlaylistLogins.digest(blob)
        #expect(
            PlaylistLogins.decide(local: sample, blob: changedBlob, remembered: remembered, uploading: true)
                == .adopt(changed)
        )
    }

    @Test
    func `with logins off nothing is sent and a login on a record is withdrawn`() {
        #expect(PlaylistLogins.decide(local: sample, blob: nil, remembered: nil, uploading: false) == .none)
        #expect(PlaylistLogins.decide(local: sample, blob: blob, remembered: nil, uploading: false) == .withdraw)
        #expect(PlaylistLogins.decide(local: nil, blob: blob, remembered: nil, uploading: false) == .withdraw)
    }

    @Test
    func `a blob that cannot be read is not adopted`() {
        #expect(PlaylistLogins
            .decide(local: nil, blob: Data("nonsense".utf8), remembered: nil, uploading: true) == .none)
    }

    @Test
    func `a digest identifies a blob without holding the password`() {
        let digest = PlaylistLogins.digest(blob)

        #expect(digest.count == 64)
        #expect(!digest.contains("s3cret"))
        #expect(PlaylistLogins.digest(blob) == digest)
        #expect(PlaylistLogins.digest(changedBlob) != digest)
    }
}

@Suite("Playlist logins on the library", .serialized)
@MainActor
struct PlaylistLoginsLibraryTests {
    @Test
    func `a playlist added with logins on carries its login on the record, and with them off does not`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }

        app.services.library.syncsLogins = { true }
        let withLogins = try await app.services.library.add(.xtream(
            name: "On",
            baseURL: panel,
            username: "a",
            password: "b"
        ))
        app.services.library.syncsLogins = { false }
        let without = try await app.services.library.add(.xtream(
            name: "Off",
            baseURL: panel,
            username: "c",
            password: "d"
        ))

        let records = try app.storedRecords()
        let onBlob = records.first { $0.id == withLogins.id }?.encryptedLogin
        #expect(onBlob.flatMap(PlaylistLogins.decode)?.password == "b")
        #expect(records.first { $0.id == without.id }?.encryptedLogin == nil)
    }

    @Test
    func `turning logins off withdraws them from the records, turning them on sends them again`() async throws {
        let app = try TestApp(transport: FakePanel().transport())
        defer { app.cleanUp() }
        app.services.library.syncsLogins = { true }
        let playlist = try await app.services.library.add(.xtream(
            name: "P",
            baseURL: panel,
            username: "a",
            password: "b"
        ))

        app.services.library.syncsLogins = { false }
        app.services.library.reconcileLogins()
        #expect(try app.storedRecords().first { $0.id == playlist.id }?.encryptedLogin == nil)

        app.services.library.syncsLogins = { true }
        app.services.library.reconcileLogins()
        #expect(try app.storedRecords().first { $0.id == playlist.id }?.encryptedLogin != nil)
    }

    @Test
    func `a playlist that arrives with its login on the record can be used here, with no login stored here`(
    ) async throws {
        let app = try TestApp(transport: FakePanel(live: 3, movies: 1).transport())
        defer { app.cleanUp() }
        app.services.library.syncsLogins = { true }
        let record = PlaylistRecord(
            id: "from-elsewhere",
            name: "Elsewhere",
            kind: .xtream,
            displayHost: "panel.example"
        )
        record.encryptedLogin = PlaylistLogins.encode(
            PlaylistSecret(url: panel, username: "alice", password: "s3cret", guideURL: nil)
        )
        let other = ModelContext(app.cloud)
        other.insert(record)
        try other.save()
        #expect(try app.credentials.load(for: "from-elsewhere") == nil)

        await app.services.library.applyRemoteChanges()
        await app.services.sync.waitForCompletion("from-elsewhere")

        #expect(try app.credentials.load(for: "from-elsewhere")?.password == "s3cret")
        #expect(try await app.services.catalogStore.entryCount(kind: .live, playlist: "from-elsewhere") == 3)
    }

    @Test
    func `with logins off, a login that arrives on a record is not taken`() async throws {
        let app = try TestApp(transport: FakePanel(live: 3, movies: 1).transport())
        defer { app.cleanUp() }
        app.services.library.syncsLogins = { false }
        let record = PlaylistRecord(
            id: "from-elsewhere",
            name: "Elsewhere",
            kind: .xtream,
            displayHost: "panel.example"
        )
        record.encryptedLogin = PlaylistLogins.encode(
            PlaylistSecret(url: panel, username: "alice", password: "s3cret", guideURL: nil)
        )
        let other = ModelContext(app.cloud)
        other.insert(record)
        try other.save()

        await app.services.library.applyRemoteChanges()

        #expect(try app.credentials.load(for: "from-elsewhere") == nil)
        #expect(try app.storedRecords().first?.encryptedLogin == nil, "and it is taken off the record")
    }
}
