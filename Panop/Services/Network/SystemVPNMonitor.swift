import CFNetwork
import Foundation
import Network
import Observation
import PanopCore

/// Whether a VPN (another app's, or the system's) is up on this device, and the rule "provider traffic
/// only while one is" that the person can switch on. It sets `ProviderNetwork.shared.block`, which every
/// request and every stream start reads, so the rule is enforced in one place.
///
/// The interfaces come from the system proxy settings' scoped entries, the usual way to see a VPN without
/// a Network Extension; a path update is only the cue to look again. Best effort: verify on each platform.
@MainActor
@Observable
final class SystemVPNMonitor {
    static let shared = SystemVPNMonitor()
    nonisolated static let requireKey = "panop.vpn.require"

    private(set) var isVPNActive = false
    private(set) var block: NetworkBlock?

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let network: ProviderNetwork
    @ObservationIgnored private var started = false

    init(defaults: UserDefaults = .standard, network: ProviderNetwork = .shared) {
        self.defaults = defaults
        self.network = network
    }

    /// Looks now, so the rule holds from the first request, then again whenever the network changes.
    func start() {
        guard !started else { return }
        started = true
        refresh()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start(queue: DispatchQueue(label: "panop.vpn-monitor", qos: .utility))
    }

    /// Reads the switch and the interfaces again. Called when either may have changed.
    func refresh() {
        let interfaces = Self.scopedInterfaces()
        isVPNActive = VPNDetector.isActive(interfaces: interfaces)
        let reason = VPNDetector.block(requireVPN: defaults.bool(forKey: Self.requireKey), interfaces: interfaces)
        block = reason
        network.setSystemBlock(reason)
    }

    private nonisolated static func scopedInterfaces() -> [String] { // swiftlint:disable:this modifier_order
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = settings["__SCOPED__"] as? [String: Any]
        else { return [] }
        return Array(scoped.keys)
    }
}
