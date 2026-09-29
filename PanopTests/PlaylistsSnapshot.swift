#if os(macOS)
    import Foundation
    @testable import Panop
    import PanopCore
    import SwiftUI
    import Testing

    /// Renders the playlists rows to /tmp/panop-playlists.png so a person can look at
    /// them. Not an assertion about pixels. Off unless `PANOP_SNAPSHOT=1`:
    ///
    ///     TEST_RUNNER_PANOP_SNAPSHOT=1 xcodebuild test -project Panop.xcodeproj \
    ///       -scheme PanopTests -destination 'platform=macOS' -only-testing:PanopTests/PlaylistsSnapshot
    ///
    /// Drawn in a real `NSWindow`, because `ImageRenderer` cannot draw AppKit-backed
    /// controls such as `Menu` (it shows a "not supported" placeholder instead).
    @Suite("Playlists snapshot", .enabled(if: ProcessInfo.processInfo.environment["PANOP_SNAPSHOT"] == "1"))
    @MainActor
    struct PlaylistsSnapshot {
        @Test
        func `render`() async throws {
            let app = try TestApp(transport: FakePanel(live: 40, movies: 10).transport())
            defer { app.cleanUp() }
            let one = try await app.services.library.add(.xtream(
                name: "Home Xtream",
                baseURL: "http://panel.example:8080",
                username: "a",
                password: "b"
            ))
            await app.services.sync.waitForCompletion(one.id)
            let file = try writeTemporaryFile(playlistText(live: 0 ..< 12))
            let two = try await app.services.library.add(.m3uFile(
                name: "Sports M3U",
                fileURL: URL(fileURLWithPath: file)
            ))
            await app.services.sync.waitForCompletion(two.id)
            let three = try await app.services.library.add(.xtream(
                name: "Backup",
                baseURL: "http://backup.example",
                username: "a",
                password: "b"
            ))
            await app.services.sync.waitForCompletion(three.id)
            app.services.syncStatus.set(
                .failed("Could not reach the provider. Check the address and your connection."),
                for: three.id
            )

            let view = VStack(spacing: 0) {
                ForEach(app.services.library.playlists) { playlist in
                    PlaylistRow(playlist: playlist, onDelete: {})
                        .padding(.horizontal, 16)
                    Divider()
                }
            }
            .environment(app.services.library)
            .environment(app.services.syncStatus)
            .frame(width: 560)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            // A real window, because AppKit-backed controls (Menu, List) cannot be drawn by ImageRenderer.
            let hosting = NSHostingView(rootView: view)
            let size = hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderFrontRegardless()
            // Let SwiftUI lay out and draw. Sleeping yields to the main run loop.
            try await Task.sleep(for: .milliseconds(800))
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/panop-playlists.png"))
            window.close()
        }
    }
#endif
