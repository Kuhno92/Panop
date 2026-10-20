import SwiftUI

/// "Require a VPN": Panop's connections to the providers wait while no VPN is active on the device. The
/// VPN itself is another app's (Proton, Mullvad, a router); Panop only checks that one is there.
struct VPNSection: View {
    @AppStorage(SystemVPNMonitor.requireKey) private var requiresVPN = false
    private var monitor: SystemVPNMonitor {
        .shared
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
        if !requiresVPN, monitor.isVPNActive {
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
        requiresVPN && !monitor.isVPNActive ? "exclamationmark.shield.fill" : "checkmark.shield.fill"
    }

    private var tint: Color {
        requiresVPN && !monitor.isVPNActive ? .orange : .secondary
    }
}
