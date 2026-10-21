import Foundation
@testable import Panop
import PanopCore
import SwiftData
import Testing

private let key = Data(repeating: 7, count: 32).base64EncodedString()
private let other = Data(repeating: 9, count: 32).base64EncodedString()
private let config = """
[Interface]
PrivateKey = \(key)
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
PublicKey = \(other)
AllowedIPs = 0.0.0.0/0
Endpoint = 203.0.113.9:51820
"""

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

@MainActor
private struct Device {
    let controller: TunnelController
    let store: InMemoryVPNConfigStore

    init(cloud: VPNSyncStore, stored: String? = nil, syncs: Bool = true) {
        store = InMemoryVPNConfigStore(stored)
        controller = TunnelController(
            store: store, makeBackend: { NoBackend() }, network: ProviderNetwork(),
            defaults: UserDefaults(suiteName: "vpn-sync-\(UUID().uuidString)")!
        )
        controller.attach(sync: cloud)
        controller.syncsConfig = { syncs }
    }
}

@Suite("VPN configuration sync", .serialized)
@MainActor
struct VPNConfigSyncTests {
    private func cloud() throws -> VPNSyncStore {
        try VPNSyncStore(context: ModelContext(PanopContainers.makeCloud(inMemory: true)))
    }

    @Test func `a configuration added on one device reaches another`() throws {
        let shared = try cloud()
        let phone = Device(cloud: shared)
        try phone.controller.importConfiguration(config)
        #expect(shared.record.blob != nil)

        let appleTV = Device(cloud: shared)
        appleTV.controller.reconcile()
        #expect(appleTV.controller.hasConfiguration)
        #expect(appleTV.controller.config?.endpointHost == "203.0.113.9")
        #expect(appleTV.store.load() != nil)
        // Using it stays each device's own choice.
        #expect(!appleTV.controller.isEnabled)
    }

    @Test func `with the setting off nothing is sent`() throws {
        let shared = try cloud()
        let phone = Device(cloud: shared, syncs: false)
        try phone.controller.importConfiguration(config)
        #expect(shared.record.blob == nil)
    }

    @Test func `turning the setting off withdraws it from the record`() throws {
        let shared = try cloud()
        let phone = Device(cloud: shared)
        try phone.controller.importConfiguration(config)
        phone.controller.syncsConfig = { false }
        phone.controller.reconcile()
        #expect(shared.record.blob == nil)
        #expect(phone.controller.hasConfiguration)
    }

    @Test func `removing it on one device removes it on the others`() throws {
        let shared = try cloud()
        let phone = Device(cloud: shared)
        try phone.controller.importConfiguration(config)
        let appleTV = Device(cloud: shared)
        appleTV.controller.reconcile()
        #expect(appleTV.controller.hasConfiguration)

        phone.controller.removeConfiguration()
        #expect(shared.record.removed)
        appleTV.controller.reconcile()
        #expect(!appleTV.controller.hasConfiguration)
        #expect(appleTV.store.load() == nil)
    }

    @Test func `a record that cannot be read as a configuration is left alone`() throws {
        let shared = try cloud()
        shared.setBlob(Data("not a configuration".utf8))
        let appleTV = Device(cloud: shared)
        appleTV.controller.reconcile()
        #expect(!appleTV.controller.hasConfiguration)
        #expect(shared.record.blob != nil)
    }
}
