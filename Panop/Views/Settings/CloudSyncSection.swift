import SwiftUI

/// iCloud: whether favourites, what was watched and the playlists follow the person to their other devices,
/// and whether the playlists' logins go with them. What actually happened at launch is said plainly, since
/// the switch alone does not tell: mirroring needs this build to be allowed and an account to be signed in.
struct CloudSyncSection: View {
    @Environment(CloudSyncStatus.self) private var status
    @Environment(PlaylistLibrary.self) private var library
    @AppStorage(CloudSync.enabledKey) private var isOn = true
    @AppStorage(CloudSync.loginsKey) private var syncsLogins = true
    @Environment(UserStateStore.self) private var userState
    @Environment(SportsAccount.self) private var sportsAccount
    @Environment(SportsSyncStore.self) private var sportsSync
    @Environment(\.cloudModelContext) private var cloudContext
    @State private var confirmsClear = false
    @State private var isClearing = false
    @State private var clearResult: SyncedDataResetResult?

    var body: some View {
        // A test run never uses iCloud, so there is nothing to set.
        if status.availability != .testing {
            Section {
                Toggle("Sync with iCloud", isOn: $isOn)
                if isOn {
                    Toggle("Include provider logins", isOn: $syncsLogins)
                }
                Label(message, systemImage: symbol)
                    .font(.footnote)
                    .foregroundStyle(tint)
                clearRow
                if isOn, status.availability == .active {
                    LabeledContent("Playlists on this device", value: String(library.playlists.count))
                    LabeledContent("Last update from iCloud") {
                        if let last = status.lastImport {
                            Text(last, style: .relative)
                        } else {
                            Text("None yet")
                        }
                    }
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("""
                Favourites, what you watched, hidden titles and your playlists are kept in your own iCloud, where \
                only you can read them. Logins are encrypted before they leave this device. \
                A change here takes effect the next time Panop opens.
                """)
            }
            if isOn {
                Section {
                    Label("Use the same Apple Account on every device.", systemImage: "1.circle.fill")
                    Label("Turn on Sync with iCloud on each of them.", systemImage: "2.circle.fill")
                    Label(
                        "Open Panop on the new device. What the others saved arrives in a minute or two; they do not need to be on.",
                        systemImage: "3.circle.fill"
                    )
                } header: {
                    Text("To sync another device")
                } footer: {
                    Text("""
                    A device with no playlists yet asks before it downloads the channels of what arrives. \
                    A playlist removed on one device is removed on the others.
                    """)
                }
            }
        }
    }

    // MARK: - Clear synced data

    /// With sync on, iCloud takes this device's data; otherwise everything is cleared. See `SyncedDataReset`.
    private var replaces: Bool {
        ICloudWipeRoute.route(for: status.availability) == .replace
    }

    @ViewBuilder
    private var clearRow: some View {
        Button(role: .destructive) {
            confirmsClear = true
        } label: {
            HStack {
                Text(replaces ? "Replace iCloud data with this device" : "Clear synced data")
                if isClearing {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isClearing || cloudContext == nil)
        .accessibilityIdentifier("clearSyncedData")
        .confirmationDialog(
            replaces ? "Replace the data in iCloud?" : "Clear all synced data?",
            isPresented: $confirmsClear, titleVisibility: .visible
        ) {
            Button(replaces ? "Replace" : "Clear", role: .destructive) { clear() }
        } message: {
            Text(clearWarning)
        }
        if let clearResult {
            Label(
                resultText(clearResult),
                systemImage: clearResult.isComplete ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(clearResult.isComplete ? Color.secondary : Color.orange)
        }
    }

    private var clearWarning: String {
        switch ICloudWipeRoute.route(for: status.availability) {
        case .replace:
            String(localized: """
            What is in your iCloud is deleted and replaced with what is on this device: your playlists, favourites, \
            what you watched, choices and keys. Your other devices take this device's data over, and what only they \
            had is gone. Nothing on this device is deleted.
            """)
        case .wipe:
            clearsWhat + " " +
                String(localized: "iCloud sync is off here, but the data in your iCloud is deleted as well.")
        case .unavailable:
            clearsWhat
        }
    }

    private var clearsWhat: String {
        String(localized: """
        Your playlists with their logins, favourites, what you watched, hidden titles, category and sports choices, \
        the sports key and the VPN configuration are deleted from this device.
        """)
    }

    private func clear() {
        guard let container = cloudContext?.container else { return }
        isClearing = true
        clearResult = nil
        let reset = SyncedDataReset(
            library: library, userState: userState, sportsSync: sportsSync, sportsAccount: sportsAccount,
            cloud: container
        )
        let availability = status.availability
        Task {
            clearResult = await reset.run(availability: availability)
            isClearing = false
        }
    }

    private func resultText(_ result: SyncedDataResetResult) -> String {
        var parts: [String] = []
        if !result.playlistsKept.isEmpty {
            parts
                .append(
                    String(
                        localized: "These playlists could not be deleted: \(result.playlistsKept.joined(separator: ", "))."
                    )
                )
        }
        switch result.iCloud {
        case .replaced:
            parts
                .append(
                    String(localized: "iCloud was wiped and now takes this device's data. Your other devices follow.")
                )
        case let .wiped(zones):
            parts.append(zones > 0
                ? String(localized: "Cleared here and in iCloud.")
                : String(localized: "Cleared here. There was nothing in iCloud."))
        case .nothingToWipe:
            parts.append(String(localized: "Cleared on this device."))
        case let .failed(reason):
            parts.append(String(localized: "iCloud could not be wiped: \(reason)"))
        }
        return parts.joined(separator: " ")
    }

    private var message: String {
        if !isOn {
            return String(localized: "Off. Everything stays on this device.")
        }
        switch status.availability {
        case .active:
            return String(localized: "On. Your data is syncing with iCloud.")
        case .off, .testing:
            return String(localized: "Turns on the next time Panop opens.")
        case .noAccount:
            return String(localized: "Sign in to iCloud in the system settings to sync.")
        case .notEntitled:
            return String(localized: "This build of Panop cannot use iCloud.")
        case .failed:
            return String(localized: "iCloud could not be opened, so this device's own copy is in use.")
        }
    }

    private var symbol: String {
        switch status.availability {
        case .active where isOn: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        case .noAccount, .notEntitled: "icloud.slash"
        default: "icloud"
        }
    }

    private var tint: Color {
        switch status.availability {
        case .failed: .orange
        case .active where isOn: .green
        default: .secondary
        }
    }
}
