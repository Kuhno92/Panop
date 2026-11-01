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

        reset = SyncedDataReset(
            library: app.services.library, userState: app.services.userState, sportsSync: app.services.sportsSync,
            sportsAccount: account, tunnel: tunnel, wiper: wiper, defaults: defaults
        )
    }

    func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        try ModelContext(app.cloud).fetchCount(FetchDescriptor<Model>())
    }
}

@Suite("Clear synced data", .serialized)
@MainActor
struct SyncedDataResetTests {
    @Test func `everything that syncs is gone afterwards, on this device`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        #expect(try fixture.count(PlaylistRecord.self) == 2)

        let result = await fixture.reset.run(availability: .active)

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

    @Test func `with sync on, the cleared state is what iCloud holds: markers, and no direct wipe`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }

        let result = await fixture.reset.run(availability: .active)

        #expect(result.iCloud == .carriedBySync)
        #expect(fixture.wiper.callCount == 0)
        // The other devices must be told to let go, not left to send their own copy back.
        #expect(fixture.app.services.sportsSync.keyRecord.removed)
        #expect(fixture.app.services.sportsSync.keyRecord.blob == nil)
        #expect(fixture.vpnSync.record.removed)
        #expect(fixture.vpnSync.record.blob == nil)
    }

    @Test func `with sync off, iCloud is wiped directly, once`() async throws {
        let fixture = try Fixture(syncs: false)
        defer { fixture.app.cleanUp() }

        let result = await fixture.reset.run(availability: .off)

        #expect(result.iCloud == .wiped(zones: 1))
        #expect(fixture.wiper.callCount == 1)
        #expect(result.isComplete)
        #expect(try fixture.count(PlaylistRecord.self) == 0)
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

    @Test func `where iCloud cannot be used the wiper is not called`() async throws {
        for availability in [CloudSync.Availability.noAccount, .notEntitled, .testing] {
            let fixture = try Fixture(syncs: false)
            defer { fixture.app.cleanUp() }
            let result = await fixture.reset.run(availability: availability)
            #expect(result.iCloud == .nothingToWipe)
            #expect(fixture.wiper.callCount == 0)
        }
    }

    @Test func `the next playlists to arrive from iCloud are offered again, as on a first launch`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        #expect(fixture.defaults.bool(forKey: PlaylistLibrary.offerDecidedKey))

        _ = await fixture.reset.run(availability: .active)

        #expect(fixture.defaults.object(forKey: PlaylistLibrary.offerDecidedKey) == nil)
    }

    @Test func `running it again, with nothing left, is harmless`() async throws {
        let fixture = try Fixture(syncs: true)
        defer { fixture.app.cleanUp() }
        _ = await fixture.reset.run(availability: .active)

        let again = await fixture.reset.run(availability: .active)

        #expect(again.isComplete)
        #expect(try fixture.count(PlaylistRecord.self) == 0)
    }

    @Test func `which way iCloud is handled follows the availability`() {
        #expect(ICloudWipeRoute.route(for: .active) == .mirrored)
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
