import SwiftUI

/// "Require a VPN": Panop's connections to the providers wait while no VPN is active on the device. The
/// VPN itself is another app's (Proton, Mullvad, a router); Panop only checks that one is there.
struct VPNSection: View {
    @AppStorage(SystemVPNMonitor.requireKey) private var requiresVPN = false
    @AppStorage(TunnelController.enabledKey) private var builtInIsOn = false
    private var monitor: SystemVPNMonitor {
        .shared
    }

    private var tunnel: TunnelController {
        .shared
    }

    /// Whether a required VPN is in place. Panop's own tunnel counts as one: with it on, the requirement is met
    /// when it is up (and traffic is held when it is not). Otherwise a VPN active on the device is needed.
    private var satisfied: Bool {
        guard requiresVPN else { return true }
        return builtInIsOn ? tunnel.state == .connected : monitor.isVPNActive
    }

    var body: some View {
        Section {
            Toggle("Require a VPN", isOn: $requiresVPN)
                .onChange(of: requiresVPN) { _, _ in monitor.refresh() }
            Label(message, systemImage: symbol)
                .font(.footnote)
                .foregroundStyle(tint)
        } header: {
            Text("Privacy")
        } footer: {
            Text("""
            With this on, Panop does not load playlists, guides or artwork, and does not start a stream, \
            unless a VPN is active on this device. Turn the VPN on in its own app or in the system settings.
            """)
        }
    }

    private var message: String {
        if requiresVPN, builtInIsOn, satisfied {
            String(localized: "On. Panop's built-in VPN is connected, so Panop connects.")
        } else if requiresVPN, builtInIsOn {
            String(localized: "On. Panop's built-in VPN is not connected, so Panop is not connecting.")
        } else if !requiresVPN, monitor.isVPNActive {
            String(localized: "Off. A VPN is active on this device.")
        } else if !requiresVPN {
            String(localized: "Off. Panop connects directly.")
        } else if monitor.isVPNActive {
            String(localized: "On. A VPN is active, so Panop connects.")
        } else {
            String(localized: "On, and no VPN is active. Panop is not connecting.")
        }
    }

    private var symbol: String {
        satisfied ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    }

    private var tint: Color {
        satisfied ? .secondary : .orange
    }
}
