import Foundation
@testable import Panop
import PanopCore
import Testing

private final class FakeBackend: TunnelBackend, @unchecked Sendable {
    enum Outcome { case ready, notReady, invalid }
    private let lock = NSLock()
    private var stops = 0
    let outcome: Outcome
    let endpoint = ProxyEndpoint(socksPort: 41080, httpPort: 41081, username: "u", password: "p")

    init(_ outcome: Outcome = .ready) {
        self.outcome = outcome
    }

    var stopCount: Int {
        lock.withLock { stops }
    }

    func start(config _: String) throws -> ProxyEndpoint {
        if outcome == .invalid {
            throw TunnelFailure(reason: "line 2: PrivateKey is not a valid key")
        }
        return endpoint
    }

    func waitReady(seconds _: Int) throws {
        if outcome == .notReady {
            throw TunnelFailure(reason: "the VPN server did not answer")
        }
    }

    func stop() {
        lock.withLock { stops += 1 }
    }

    var counters: TunnelCounters {
        TunnelCounters(received: 10, sent: 5, lastHandshake: nil)
    }
}

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

/// A tuple, because each test takes only the parts it looks at.
@MainActor
private func makeController(
    _ outcome: FakeBackend.Outcome = .ready,
    stored: String? = config
) -> (TunnelController, ProviderNetwork, FakeBackend, UserDefaults) { // swiftlint:disable:this large_tuple
    let backend = FakeBackend(outcome)
    let network = ProviderNetwork()
    let defaults = UserDefaults(suiteName: "tunnel-test-\(UUID().uuidString)")!
    let controller = TunnelController(
        store: InMemoryVPNConfigStore(stored), makeBackend: { backend }, network: network, defaults: defaults
    )
    return (controller, network, backend, defaults)
}

@MainActor
private func settle(_ controller: TunnelController) async {
    for _ in 0 ..< 200 where controller.state == .connecting {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("Tunnel controller", .serialized)
@MainActor
struct TunnelControllerTests {
    @Test func `traffic is held from the moment the switch goes on, before the tunnel is up`() {
        let (controller, network, _, _) = makeController()
        controller.setEnabled(true)
        #expect(controller.state == .connecting)
        #expect(network.block == .tunnelNotConnected)
    }

    @Test func `once the tunnel answers, traffic goes through its proxy`() async {
        let (controller, network, backend, _) = makeController()
        controller.setEnabled(true)
        await settle(controller)
        #expect(controller.state == .connected)
        #expect(network.block == nil)
        #expect(network.proxy == backend.endpoint)
    }

    @Test func `a tunnel that does not answer keeps traffic held, and never falls back to direct`() async {
        let (controller, network, backend, _) = makeController(.notReady)
        controller.setEnabled(true)
        await settle(controller)
        #expect(controller.state == .failed(.unreachable))
        #expect(network.block == .tunnelNotConnected)
        #expect(network.proxy == nil)
        #expect(network.tunnelIsOn)
        #expect(backend.stopCount >= 1)
    }

    @Test func `a refused configuration is reported with its line`() async {
        let (controller, network, _, _) = makeController(.invalid)
        controller.setEnabled(true)
        await settle(controller)
        #expect(controller.state == .failed(.invalid("line 2: PrivateKey is not a valid key")))
        #expect(network.block == .tunnelNotConnected)
    }

    @Test func `switching it off returns to a direct connection`() async {
        let (controller, network, backend, _) = makeController()
        controller.setEnabled(true)
        await settle(controller)
        controller.setEnabled(false)
        #expect(controller.state == .off)
        #expect(network.block == nil)
        #expect(!network.tunnelIsOn)
        #expect(backend.stopCount >= 1)
    }

    @Test func `with no stored configuration it stays held rather than connecting direct`() async {
        let (controller, network, _, _) = makeController(stored: nil)
        controller.setEnabled(true)
        await settle(controller)
        #expect(controller.state == .failed(.noConfiguration))
        #expect(network.block == .tunnelNotConnected)
    }

    @Test func `launch holds traffic at once when the switch was left on`() {
        let (controller, network, _, defaults) = makeController()
        defaults.set(true, forKey: TunnelController.enabledKey)
        controller.launch()
        #expect(network.block == .tunnelNotConnected)
    }

    @Test func `launch with the switch off changes nothing`() {
        let (controller, network, _, _) = makeController()
        controller.launch()
        #expect(controller.state == .off)
        #expect(network.block == nil)
    }

    @Test func `importing a bad configuration throws by line and keeps the old one`() throws {
        let (controller, _, _, _) = makeController()
        #expect(throws: WireGuardConfig.ParseError.self) {
            try controller.importConfiguration("[Interface]\nPrivateKey = nope\n")
        }
        #expect(controller.hasConfiguration)
        #expect(controller.config?.endpointHost == "203.0.113.9")
    }

    @Test func `removing the configuration turns the tunnel off`() async {
        let (controller, network, _, defaults) = makeController()
        controller.setEnabled(true)
        await settle(controller)
        controller.removeConfiguration()
        #expect(!controller.hasConfiguration)
        #expect(!controller.isEnabled)
        #expect(defaults.bool(forKey: TunnelController.enabledKey) == false)
        #expect(network.block == nil)
    }

    @Test func `the system VPN rule applies only to a direct route`() async {
        let (controller, network, _, _) = makeController()
        network.setSystemBlock(.vpnRequired)
        #expect(network.block == .vpnRequired)
        controller.setEnabled(true)
        await settle(controller)
        // The tunnel is the VPN: a system VPN is not also required.
        #expect(network.block == nil)
        controller.setEnabled(false)
        #expect(network.block == .vpnRequired)
    }
}
