import Foundation
@testable import Panop
import PanopCore
import SwiftData
import Testing

private final class FakeWiper: CloudDataWiper, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let outcome: Result<Int, CloudWipeError>

    init(_ outcome: Result<Int, CloudWipeError> = .success(1)) {
        self.outcome = outcome
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func wipe() async throws -> Int {
        lock.withLock { calls += 1 }
        return try outcome.get()
    }
}

private struct NoBackend: TunnelBackend {
    func start(config _: String) throws -> ProxyEndpoint {
        throw TunnelFailure(reason: "unused")
    }

    func waitReady(seconds _: Int) throws {}
    func stop() {}
    var counters: TunnelCounters {
        TunnelCounters()
    }
}

private let key = Data(repeating: 7, count: 32).base64EncodedString()
private let other = Data(repeating: 9, count: 32).base64EncodedString()
private let wireGuard = """
[Interface]
PrivateKey = \(key)
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
PublicKey = \(other)
AllowedIPs = 0.0.0.0/0
Endpoint = 203.0.113.9:51820
"""

/// An app with something of every kind synced, and a reset wired to it.
@MainActor
private struct Fixture {
    let app: TestApp
    let account: SportsAccount
    let tunnel: TunnelController
    let defaults: UserDefaults
    let wiper: FakeWiper
    let reset: SyncedDataReset
    let vpnSync: VPNSyncStore
    let snapshotFile: URL

    init(syncs: Bool, wiper: FakeWiper = FakeWiper()) throws {
        app = try TestApp(transport: FakePanel(live: 3, movies: 1).transport())
        defaults = UserDefaults(suiteName: "reset-\(UUID().uuidString)") ?? .standard
        defaults.set(true, forKey: PlaylistLibrary.offerDecidedKey)
        self.wiper = wiper

        let context = ModelContext(app.cloud)
        for number in 1 ... 2 {
            context.insert(PlaylistRecord(
                id: "p\(number)",
                name: "Playlist \(number)",
                kind: .xtream,
                displayHost: "h"
            ))
            try app.credentials.save(
                PlaylistSecret(url: "http://h", username: "u", password: "p", guideURL: nil),
                for: "p\(number)"
            )
        }
        context.insert(UserContentState(streamID: "p1|e1", isFavorite: true))
        context.insert(UserContentState(streamID: "p2|e9", isFavorite: true))
        context.insert(CategoryPreference(kindRaw: "live", name: "Sport", isHidden: true))
        context.insert(SportsPreference(kind: "league", key: "78", value: "Bundesliga"))
        try context.save()
        app.services.library.reload()
        app.services.userState.reload()

        account = SportsAccount(
            keyStore: InMemorySportsKeyStore("sk_secret_key"), sync: app.services.sportsSync,
            transport: FakePanel(live: 1, movies: 0).transport(), memory: SportsKeyMemory(defaults: defaults)
        )
        account.syncsKey = { syncs }

        vpnSync = VPNSyncStore(context: ModelContext(app.cloud))
        tunnel = TunnelController(
            store: InMemoryVPNConfigStore(wireGuard), makeBackend: { NoBackend() }, network: ProviderNetwork(),
            defaults: defaults
        )
        tunnel.attach(sync: vpnSync)
        tunnel.syncsConfig = { syncs }

        snapshotFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-\(UUID().uuidString).json")
        reset = SyncedDataReset(
            library: app.services.library, userState: app.services.userState, sportsSync: app.services.sportsSync,
            sportsAccount: account, cloud: app.cloud, tunnel: tunnel, wiper: wiper, defaults: defaults,
            snapshotFile: snapshotFile, settleDelay: .zero
        )
    }

    func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        try ModelContext(app.cloud).fetchCount(FetchDescriptor<Model>())
    }
}

@Suite("Clear synced data", .serialized)
@MainActor
struct SyncedDataResetTests {
    // MARK: - Sync off: everything is cleared

    @Test func `everything that syncs is gone afterwards, on this device`() async throws {
        let fixture = try Fixture(syncs: false)
        defer { fixture.app.cleanUp() }
        #expect(try fixture.count(PlaylistRecord.self) == 2)

        let result = await fixture.reset.run(availability: .off)

        #expect(result.isComplete)
        #expect(fixture.app.services.library.playlists.isEmpty)
        #expect(try fixture.count(PlaylistRecord.self) == 0)
        #expect(try fixture.count(UserContentState.self) == 0)
        #expect(try fixture.count(CategoryPreference.self) == 0)
        #expect(try fixture.count(SportsPreference.self) == 0)
        #expect(try fixture.app.credentials.load(for: "p1") == nil)
        #expect(try fixture.app.credentials.load(for: "p2") == nil)
        #expect(fixture.account.hasKey == false)
        #expect(fixture.tunnel.hasConfiguration == false)
        #expect(fixture.app.services.userState.favorites.isEmpty)
    }

    @Test func `with sync off, iCloud is wiped directly, once`() async throws {
        let fixture = try Fixture(syncs: false)
        defer { fixture.app.cleanUp() }

        let result = await fixture.reset.run(availability: .off)

        #expect(result.iCloud == .wiped(zones: 1))
        #expect(fixture.wiper.callCount == 1)
        #expect(result.isComplete)
    }

    @Test func `a wipe that fails is reported and leaves this device cleared`() async throws {
        let fixture = try Fixture(syncs: false, wiper: FakeWiper(.failure(.unreachable)))
        defer { fixture.app.cleanUp() }

        let result = await fixture.reset.run(availability: .off)

        guard case let .failed(reason) = result.iCloud else {
            Issue.record("expected a failure, got \(result.iCloud)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(!result.isComplete)
        #expect(try fixture.count(PlaylistRecord.self) == 0)
        #expect(fixture.account.hasKey == false)
    }

    @Test func `no account is nothing to wipe, not a failure`() async throws {
        let fixture = try Fixture(syncs: false, wiper: FakeWiper(.failure(.noAccount)))
        defer { fixture.app.cleanUp() }

        let result = await fixture.reset.run(availability: .off)

        #expect(result.iCloud == .nothingToWipe)
        #expect(result.isComplete)
    }

    @Test func `where iCloud cannot be used the wiper is not called, and this device is cleared`() async throws {
        for availability in [CloudSync.Availability.noAccount, .notEntitled, .testing] {
            let fixture = try Fixture(syncs: false)
            defer { fixture.app.cleanUp() }
            let result = await fixture.reset.run(availability: availability)
            #expect(result.iCloud == .nothingToWipe)
            #expect(fixture.wiper.callCount == 0)
            #expect(try fixture.count(PlaylistRecord.self) == 0)
        }
    }

    @Test func `the next playlists to arrive from iCloud are offered again, as on a first launch`() async throws {
        let fixture = try Fixture(syncs: false)
        defer { fixture.app.cleanUp() }
        #expect(fixture.defaults.bool(forKey: PlaylistLibrary.offerDecidedKey))

        _ = await fixture.reset.run(availability: .off)

        #expect(fixture.defaults.object(forKey: PlaylistLibrary.offerDecidedKey) == nil)
    }

    @Test func `running it again, with nothing left, is harmless`() async throws {
        let fixture = try Fixture(syncs: false)
        defer { fixture.app.cleanUp() }
        _ = await fixture.reset.run(availability: .off)

        let again = await fixture.reset.run(availability: .off)

        #expect(again.isComplete)
        #expect(try fixture.count(PlaylistRecord.self) == 0)
    }

    // MARK: - Sync on: iCloud takes this device's data

    @Test func `with sync on, iCloud is wiped once and nothing on this device is cleared`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }

        let result = await fixture.reset.run(availability: .active)
        await fixture.reset.settling?.value

        #expect(result.iCloud == .replaced)
        #expect(result.isComplete)
        #expect(fixture.wiper.callCount == 1)
        #expect(try fixture.count(PlaylistRecord.self) == 2)
        #expect(try fixture.count(UserContentState.self) == 2)
        #expect(try fixture.count(CategoryPreference.self) == 1)
        #expect(try fixture.count(SportsPreference.self) == 1)
        #expect(fixture.app.services.library.playlists.map(\.id).sorted() == ["p1", "p2"])
        #expect(try fixture.app.credentials.load(for: "p1") != nil, "the logins stay in the Keychain")
        #expect(fixture.account.hasKey)
        #expect(fixture.tunnel.hasConfiguration)
        #expect(fixture.app.services.userState.favorites.count == 2)
    }

    @Test func `the rows are written again, so mirroring has something to send to the new zone`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        let before = try Set(ModelContext(fixture.app.cloud).fetch(FetchDescriptor<UserContentState>())
            .map(\.persistentModelID))

        _ = await fixture.reset.run(availability: .active)
        await fixture.reset.settling?.value

        let after = try Set(ModelContext(fixture.app.cloud).fetch(FetchDescriptor<UserContentState>())
            .map(\.persistentModelID))
        #expect(after.count == 2)
        #expect(before.isDisjoint(with: after), "new rows, not the old ones left as they were")
    }

    @Test func `if mirroring empties this device when the zone goes, what was here is put back`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        _ = await fixture.reset.run(availability: .active)

        // What a mirror may do on seeing its zone deleted.
        let context = ModelContext(fixture.app.cloud)
        try context.delete(model: PlaylistRecord.self)
        try context.delete(model: UserContentState.self)
        try context.delete(model: CategoryPreference.self)
        try context.delete(model: SportsPreference.self)
        try context.save()
        await fixture.reset.settling?.value

        #expect(try fixture.count(PlaylistRecord.self) == 2)
        #expect(try fixture.count(UserContentState.self) == 2)
        #expect(try fixture.count(CategoryPreference.self) == 1)
        #expect(try fixture.count(SportsPreference.self) == 1)
        #expect(fixture.app.services.library.playlists.count == 2)
    }

    @Test func `putting back never makes a second copy`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        _ = await fixture.reset.run(availability: .active)
        await fixture.reset.settling?.value
        let snapshot = SyncedSnapshot.capture(from: ModelContext(fixture.app.cloud))

        #expect(snapshot.insertMissing(into: ModelContext(fixture.app.cloud)) == 0)
        #expect(try fixture.count(PlaylistRecord.self) == 2)
        #expect(try fixture.count(UserContentState.self) == 2)
    }

    @Test func `the snapshot on disk is kept until the write-back is done, then removed`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        let result = await fixture.reset.run(availability: .active)
        #expect(result.iCloud == .replaced)
        await fixture.reset.settling?.value

        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotFile.path))
    }

    @Test func `if the wipe fails, nothing was touched and no snapshot is left behind`() async throws {
        let fixture = try Fixture(syncs: true, wiper: FakeWiper(.failure(.unreachable)))
        defer { fixture.app.cleanUp() }
        let before = SyncedSnapshot.capture(from: ModelContext(fixture.app.cloud))

        let result = await fixture.reset.run(availability: .active)

        guard case .failed = result.iCloud else {
            Issue.record("expected a failure, got \(result.iCloud)")
            return
        }
        #expect(SyncedSnapshot.capture(from: ModelContext(fixture.app.cloud)) == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotFile.path))
        #expect(fixture.app.services.library.playlists.count == 2)
    }

    @Test func `an interrupted replace is finished at the next launch`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        let snapshot = SyncedSnapshot.capture(from: ModelContext(fixture.app.cloud))
        try snapshot.save(to: fixture.snapshotFile)
        let context = ModelContext(fixture.app.cloud)
        try context.delete(model: PlaylistRecord.self)
        try context.delete(model: UserContentState.self)
        try context.save()

        var refreshed = false
        SyncedDataReset.finishInterrupted(cloud: fixture.app.cloud, file: fixture.snapshotFile, delay: .zero) {
            refreshed = true
        }
        for _ in 0 ..< 100 where FileManager.default.fileExists(atPath: fixture.snapshotFile.path) {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(refreshed)
        #expect(try fixture.count(PlaylistRecord.self) == 2)
        #expect(try fixture.count(UserContentState.self) == 2)
    }

    // MARK: - The pieces

    @Test func `a snapshot survives a round trip through the file`() throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        let snapshot = SyncedSnapshot.capture(from: ModelContext(fixture.app.cloud))
        try snapshot.save(to: fixture.snapshotFile)
        defer { SyncedSnapshot.discard(at: fixture.snapshotFile) }

        #expect(SyncedSnapshot.load(from: fixture.snapshotFile) == snapshot)
        #expect(!snapshot.isEmpty)
    }

    @Test func `which way iCloud is handled follows the availability`() {
        #expect(ICloudWipeRoute.route(for: .active) == .replace)
        #expect(ICloudWipeRoute.route(for: .off) == .wipe)
        #expect(ICloudWipeRoute.route(for: .failed("x")) == .wipe)
        #expect(ICloudWipeRoute.route(for: .noAccount) == .unavailable)
        #expect(ICloudWipeRoute.route(for: .notEntitled) == .unavailable)
        #expect(ICloudWipeRoute.route(for: .testing) == .unavailable)
    }

    @Test func `only the zones SwiftData mirrors into are wiped`() {
        #expect(CloudZones.isMirror("com.apple.coredata.cloudkit.zone"))
        #expect(CloudZones.isMirror("com.apple.coredata.cloudkit.zone-2"))
        #expect(!CloudZones.isMirror("_defaultZone"))
        #expect(!CloudZones.isMirror("MyZone"))
    }
}
