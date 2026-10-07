import SwiftUI

/// iCloud: whether favourites, what was watched and the playlists follow the person to their other devices,
/// and whether the playlists' logins go with them. What actually happened at launch is said plainly, since
/// the switch alone does not tell: mirroring needs this build to be allowed and an account to be signed in.
struct CloudSyncSection: View {
    @Environment(CloudSyncStatus.self) private var status
    @Environment(PlaylistLibrary.self) private var library
    @AppStorage(CloudSync.enabledKey) private var isOn = true
    @AppStorage(CloudSync.loginsKey) private var syncsLogins = true

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
                        "Open Panop on the other device and wait a minute or two. Everything above arrives there.",
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
