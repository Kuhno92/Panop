import SwiftUI

/// What an empty device says first: it looks for the person's other devices through iCloud, offers the playlists it
/// finds there, or says plainly what to do when nothing comes. With iCloud unavailable or off it is the plain welcome.
struct SyncWelcomeView: View {
    let onAdd: () -> Void

    @Environment(PlaylistLibrary.self) private var library
    @Environment(CloudSyncStatus.self) private var cloudSync
    @State private var waited = false
    @State private var attempt = 0
    @State private var accepting = false

    private var phase: SyncWelcomePhase {
        SyncWelcomePhase.phase(availability: cloudSync.availability, offer: library.pendingOffer, waited: waited)
    }

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 16) {
                AppLogo(size: 110)
                title
            }
        } description: {
            description
        } actions: {
            actions
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        // A moment is given for the other devices to answer; after it the screen says nothing came.
        .task(id: attempt) {
            waited = false
            try? await Task.sleep(for: SyncWelcomePhase.patience)
            waited = true
        }
        .accessibilityIdentifier("syncWelcome")
    }

    @ViewBuilder
    private var title: some View {
        switch phase {
        case .offer:
            Text("Found your playlists").font(.title.bold())
        case .searching:
            Text("Looking for your other devices").font(.title.bold())
        case .nothingFound:
            Text("Nothing from iCloud yet").font(.title.bold())
        case .unavailable, .plain:
            Text("Welcome to Panop").font(.title.bold())
        }
    }

    @ViewBuilder
    private var description: some View {
        switch phase {
        case let .offer(names):
            Text("These came from your other devices through iCloud: \(names.joined(separator: ", ")). Use them here?")
        case .searching:
            VStack(spacing: 12) {
                ProgressView()
                Text("""
                If you use Panop on another device with the same Apple Account, your playlists, favourites and watched \
                titles come here by themselves. There is nothing to do on this device.
                """)
            }
        case .nothingFound:
            Text("""
            To bring your playlists from another device:
            1. Open Panop there and check that Settings > iCloud says it is on.
            2. Use the same Apple Account on both devices.
            3. Keep Panop open there for a minute, then look again here.
            """)
        case let .unavailable(availability):
            Text(unavailableText(availability))
        case .plain:
            Text("Add an M3U playlist or Xtream provider to get started.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch phase {
        case .offer:
            Button(accepting ? "Getting them…" : "Use these playlists") {
                accepting = true
                Task {
                    await library.acceptOffer()
                    accepting = false
                }
            }
            .disabled(accepting)
            Button("Add a different playlist", action: onAdd)
        case .searching:
            Button("Add a playlist instead", action: onAdd)
        case .nothingFound:
            Button("Look again") { attempt += 1 }
            Button("Add a playlist", action: onAdd)
        case .unavailable, .plain:
            Button("Add playlist", action: onAdd)
        }
    }

    private func unavailableText(_ availability: CloudSync.Availability) -> String {
        switch availability {
        case .noAccount:
            String(localized: """
            To bring your playlists from another device, sign in to iCloud in this device's system settings, then open \
            Panop again. Or add a playlist here.
            """)
        case .notEntitled:
            String(localized: "This build of Panop cannot use iCloud, so playlists have to be added here.")
        default:
            String(localized: "iCloud could not be opened, so playlists have to be added here for now.")
        }
    }
}
