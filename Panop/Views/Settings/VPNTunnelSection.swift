import PanopCore
import SwiftUI
import UniformTypeIdentifiers

/// Panop's own WireGuard tunnel: the person adds the configuration their VPN provider hands out, switches
/// it on, and every provider connection (playlists, guides, artwork, streams) goes through it. No system VPN
/// is involved; other apps on the device are not affected.
struct VPNTunnelSection: View {
    @State private var tunnel = TunnelController.shared
    @Environment(CloudSyncStatus.self) private var cloud
    @AppStorage(TunnelController.syncsKey) private var syncs = true
    @AppStorage(TunnelController.enabledKey) private var isOn = false
    @State private var adding = false
    @State private var testing = false
    @State private var exitAddress: String?
    @State private var testFailed = false
    @State private var confirmsRemoval = false

    var body: some View {
        Section {
            if let config = tunnel.config {
                Toggle("Send Panop's traffic through this VPN", isOn: $isOn)
                    .onChange(of: isOn) { _, nowOn in tunnel.setEnabled(nowOn) }
                LabeledContent("Server", value: config.endpointHost)
                if cloud.availability == .active {
                    Toggle("Sync the configuration with iCloud", isOn: $syncs)
                        .onChange(of: syncs) { _, _ in tunnel.reconcile() }
                }
                Label(statusText, systemImage: statusSymbol)
                    .font(.footnote)
                    .foregroundStyle(statusTint)
                if isOn {
                    Label {
                        Text("""
                        LumeEngine and KSPlayer send their streams through the VPN directly. AVPlayer, VLC and \
                        AetherEngine play them through a local relay inside Panop. AirPlay is not available.
                        """)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if isOn, tunnel.state == .connected {
                    LabeledContent("Received", value: bytes(tunnel.counters.received))
                    LabeledContent("Sent", value: bytes(tunnel.counters.sent))
                    #if !os(tvOS)
                        testRow
                    #endif
                }
                Button("Replace configuration") { adding = true }
                Button("Remove configuration", role: .destructive) { confirmsRemoval = true }
            } else {
                Button("Add a WireGuard configuration") { adding = true }
                if cloud.availability == .active, syncs {
                    Label {
                        Text("One added on another of your devices arrives here by itself.")
                    } icon: {
                        Image(systemName: "icloud")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("VPN built into Panop")
        } footer: {
            Text("""
            Paste the WireGuard configuration your VPN provider gives you (Proton, Mullvad and others). With it on, \
            Panop sends its own playlists, guides, artwork and streams through that VPN, and nothing else on this \
            device. The private key stays in this device's Keychain. If the VPN is down, Panop does not connect.
            """)
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: $adding) { WireGuardFieldsForm(tunnel: tunnel) }
        #else
        .sheet(isPresented: $adding) { AddWireGuardSheet(tunnel: tunnel) }
        #endif
        .confirmationDialog("Remove the VPN configuration?", isPresented: $confirmsRemoval) {
            Button("Remove", role: .destructive) {
                tunnel.removeConfiguration()
                isOn = false
            }
        }
        .task(id: tunnel.state) {
            while !Task.isCancelled, tunnel.state == .connected {
                tunnel.refreshCounters()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    #if !os(tvOS)
        private var testRow: some View {
            HStack {
                Button("Test connection") {
                    testing = true
                    testFailed = false
                    Task {
                        exitAddress = await tunnel.exitAddress()
                        testFailed = exitAddress == nil
                        testing = false
                    }
                }
                .disabled(testing)
                Spacer()
                if testing {
                    ProgressView()
                } else if let exitAddress {
                    Text(exitAddress).foregroundStyle(.secondary).textSelection(.enabled)
                } else if testFailed {
                    Text("No answer").foregroundStyle(.orange)
                }
            }
        }
    #endif

    private func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }

    private var statusText: String {
        switch tunnel.state {
        case .off: String(localized: "Off. Panop connects directly.")
        case .connecting: String(localized: "Connecting …")
        case .connected: String(localized: "Connected. Panop's traffic goes through the VPN.")
        case .failed(.noConfiguration): String(localized: "No configuration. Panop is not connecting.")
        case .failed(.unreachable): String(localized: "The VPN did not answer. Panop is not connecting.")
        case .failed(.invalid): String(localized: "The configuration is not valid. Panop is not connecting.")
        case let .failed(.startFailed(detail)):
            String(localized: "The VPN could not start: \(detail). Panop is not connecting.")
        }
    }

    private var statusSymbol: String {
        switch tunnel.state {
        case .off: "shield.slash"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.shield.fill"
        case .failed: "exclamationmark.shield.fill"
        }
    }

    private var statusTint: Color {
        switch tunnel.state {
        case .connected: .green
        case .failed: .orange
        default: .secondary
        }
    }
}

#if !os(tvOS)
    /// Paste the configuration, or pick the `.conf` file. Checked before it is kept; what is wrong is said by line.
    private struct AddWireGuardSheet: View {
        let tunnel: TunnelController
        @Environment(\.dismiss) private var dismiss
        @State private var text = ""
        @State private var problem: String?
        @State private var picking = false

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextEditor(text: $text)
                            .font(.footnote.monospaced())
                            .frame(minHeight: 220)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                        Button("Choose a .conf file") { picking = true }
                    } footer: {
                        if let problem {
                            Text(problem).foregroundStyle(.orange)
                        } else {
                            Text("Paste the whole file, from [Interface] to the end of [Peer].")
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("WireGuard configuration")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") { add() }
                                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
                        guard case let .success(url) = result else { return }
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer {
                            if scoped {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        if let read = try? String(contentsOf: url, encoding: .utf8) {
                            text = read
                            add()
                        } else {
                            problem = String(localized: "That file could not be read.")
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 420)
            #endif
        }

        private func add() {
            do {
                try tunnel.importConfiguration(text)
                // The key is not kept in a view's state any longer than it must be.
                text = ""
                dismiss()
            } catch {
                problem = "\(error)"
            }
        }
    }
#endif
