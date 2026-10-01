#if os(macOS)
    import AppKit
    import SwiftData
    import SwiftUI

    enum PlayerWindow {
        static let id = "player"
    }

    /// The content of a macOS player window: looks the address up again, then plays.
    ///
    /// A window opened with `PlayerWindowRequest` has no stream address in it (see there), so a
    /// channel or film is found in the catalog by its id, and an episode builds its own from the
    /// playlist's login.
    struct PlayerWindowContent: View {
        let request: PlayerWindowRequest

        @Environment(\.modelContext) private var catalog

        var body: some View {
            PlayerScreen(target: request.target(streamURL: Self.streamURL(for: request, in: catalog)))
                .frame(minWidth: 640, minHeight: 400)
                .background(.black)
                .background(WindowCloseWatcher())
        }

        /// The address the catalog holds for this item, or nil if it holds none (an episode, or
        /// an item that has since gone). The playlist is matched as well as the id, since an id
        /// can repeat across playlists.
        static func streamURL(for request: PlayerWindowRequest, in context: ModelContext) -> String? {
            let playlist = request.playlist
            let id = request.entryID
            var descriptor = FetchDescriptor<CatalogEntryRecord>(
                predicate: #Predicate { $0.playlist == playlist && $0.id == id }
            )
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first?.streamURL
        }
    }

    /// Stops playback when the window closes, however it is closed.
    ///
    /// A closed window does not reliably take its content's `onDisappear` with it, and sound
    /// from a window that is gone is worse than a missed cleanup. The screen under it listens for
    /// this and stops.
    struct WindowCloseWatcher: NSViewRepresentable {
        func makeNSView(context: Context) -> WatcherView {
            WatcherView()
        }

        func updateNSView(_ view: WatcherView, context: Context) {}

        final class WatcherView: NSView {
            private var observer: NSObjectProtocol?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                // Dropped whenever the window changes or goes: an observer left behind would
                // stop playback for a window that is no longer this one.
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                guard let window else { return }
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    NotificationCenter.default.post(name: .playerWindowWillClose, object: nil)
                }
            }
        }
    }

    extension Notification.Name {
        /// Posted when a player window is about to close.
        static let playerWindowWillClose = Notification.Name("PanopPlayerWindowWillClose")
    }
#endif
