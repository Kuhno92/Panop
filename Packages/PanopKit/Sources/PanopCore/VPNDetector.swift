import Foundation

/// Decides, from the names of the network interfaces that carry traffic, whether a VPN is in use, and what
/// that means for provider traffic. Pure: the platform code that lists the interfaces lives in the app.
public enum VPNDetector {
    /// Interface name prefixes a VPN presents as: `utun` (WireGuard, IKEv2 on Apple platforms), `ipsec`,
    /// `ppp`, `tun` and `tap` (OpenVPN and friends).
    private static let prefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    public static func isVPNInterface(_ name: String) -> Bool {
        let lower = name.lowercased()
        return prefixes.contains { lower.hasPrefix($0) }
    }

    public static func isActive(interfaces: [String]) -> Bool {
        interfaces.contains(where: isVPNInterface)
    }

    /// What holds provider traffic back: only when the person wants a VPN and none is active.
    public static func block(requireVPN: Bool, interfaces: [String]) -> NetworkBlock? {
        requireVPN && !isActive(interfaces: interfaces) ? .vpnRequired : nil
    }
}
