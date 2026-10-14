import PanopSports
import SwiftUI

/// The sports hub in Settings: the person's own sportapi.ai key, whether it travels through iCloud, and what is left of
/// the day's requests. The hub shows nothing until a key is entered here.
struct SportsSettingsSection: View {
    @Environment(SportsAccount.self) private var account
    @Environment(SportsSyncStore.self) private var sync
    @Environment(CloudSyncStatus.self) private var cloud
    @Environment(\.sportsFeed) private var feed
    @AppStorage(SportsConfig.syncsKeyKey) private var syncsKey = true
    @State private var showsTab = true
    @State private var draft = ""
    @State private var message: String?
    @State private var confirmsRemoval = false

    private var isChecking: Bool {
        account.state == .validating
    }

    var body: some View {
        Section {
            if account.hasKey {
                keyRow
                if let quota = account.quota {
                    SettingsRow(
                        "Requests today",
                        symbol: "gauge.with.dots.needle.33percent",
                        tint: quota.isReserved ? .orange : .teal,
                        value: "\(quota.used) / \(quota.limit)"
                    )
                }
                Toggle(isOn: $syncsKey) {
                    SettingsRow("Keep the key in iCloud", symbol: "icloud", tint: .blue)
                }
                .disabled(cloud.availability != .active)
                Button("Remove key", role: .destructive) { confirmsRemoval = true }
            } else {
                entry
            }
            Toggle(isOn: $showsTab) {
                SettingsRow("Show the Sports tab", symbol: "sportscourt", tint: .green)
            }
            .onChange(of: showsTab) { _, shown in sync.setShowsTab(shown) }
        } header: {
            Text("Sports")
        } footer: {
            Text(footer)
        }
        .onAppear { showsTab = sync.showsTab() }
        .confirmationDialog("Remove the sports key?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) {
                account.removeKey()
                draft = ""
                message = nil
            }
        } message: {
            Text("With iCloud on, it is removed from your other devices too. Your leagues and teams are kept.")
        }
    }

    // MARK: - Rows

    private var keyRow: some View {
        SettingsRow(
            "sportapi.ai key", symbol: "key.fill", tint: stateTint, value: stateText
        )
    }

    @ViewBuilder
    private var entry: some View {
        SecureField("sportapi.ai key", text: $draft)
            .textContentType(.password)
            .autocorrectionDisabled()
        #if os(iOS)
            .textInputAutocapitalization(.never)
        #endif
            .onSubmit { Task { await save() } }
        Button {
            Task { await save() }
        } label: {
            HStack {
                Text("Save key")
                if isChecking {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChecking)
        if let message {
            Text(message).font(.footnote).foregroundStyle(.red)
        }
        Link(destination: SportsConfig.website) {
            SettingsRow("Get a free key", symbol: "arrow.up.right.square", tint: .gray)
        }
    }

    private func save() async {
        message = nil
        switch await account.setKey(draft) {
        case .accepted:
            draft = ""
        case .rejected:
            message = String(localized: "That key was not accepted.")
        case .unreachable:
            message = String(localized: "The service could not be reached. Check the connection and try again.")
        case .notSaved:
            message = String(localized: "The key was accepted but could not be saved on this device.")
        }
    }

    // MARK: - What it says

    private var stateText: String {
        switch account.effectiveState {
        case .noKey: String(localized: "None")
        case .validating: String(localized: "Checking…")
        case .ready: account.maskedKey ?? ""
        case .invalid: String(localized: "Not accepted")
        case let .limitReached(resetsAt):
            resetsAt
                .map {
                    String(localized: "Day's limit reached, until \($0.formatted(date: .omitted, time: .shortened))")
                }
                ?? String(localized: "Day's limit reached")
        }
    }

    private var stateTint: Color {
        switch account.effectiveState {
        case .ready: .green
        case .invalid, .limitReached: .orange
        default: .gray
        }
    }

    private var footer: String {
        if account.hasKey {
            return String(localized: """
            The key is kept in the Keychain on this device. With iCloud on it also travels, encrypted, to your other \
            devices. Only match, league and team requests go to sportapi.ai: nothing about your playlists or what you watch.
            """)
        }
        return String(localized: """
        The sports hub shows today's football matches and the channel of your playlist that has them. It uses your own \
        free account at sportapi.ai: enter its key here. The free plan allows 2,000 requests a day.
        """)
    }
}
