#if os(macOS)
    import Foundation
    @testable import Panop
    import SwiftData
    import SwiftUI
    import Testing

    /// Renders the Live TV screen in its problem states to /tmp/panop-live-*.png. Not an
    /// assertion about pixels. Off unless `PANOP_SNAPSHOT=1`.
    @Suite("Live TV snapshot", .enabled(if: ProcessInfo.processInfo.environment["PANOP_SNAPSHOT"] == "1"))
    @MainActor
    struct LiveTVSnapshot {
        private func render(_ app: TestApp, to path: String) async throws {
            let view = NavigationStack { LiveTVView() }
                .modelContainer(app.services.catalogContainer)
                .environment(app.services.library)
                .environment(app.services.syncStatus)
                .frame(width: 560, height: 420)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 420)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(1200))
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
            window.close()
        }

        @Test
        func `channels showing, one source failed`() async throws {
            let app = try TestApp(transport: FakePanel(live: 6, movies: 2).transport())
            defer { app.cleanUp() }
            let playlist = try await app.services.library.add(.xtream(
                name: "Home Xtream", baseURL: "http://panel.example:8080", username: "a", password: "b"
            ))
            await app.services.sync.waitForCompletion(playlist.id)
            app.services.syncStatus.set(
                .failed("Could not reach the provider. Check the address and your connection."),
                for: playlist.id
            )
            try await render(app, to: "/tmp/panop-live-banner.png")
        }

        @Test
        func `nothing loaded because the provider failed`() async throws {
            let app = try TestApp(transport: FakePanel(live: 0, movies: 0).transport())
            defer { app.cleanUp() }
            let playlist = try await app.services.library.add(.xtream(
                name: "Home Xtream", baseURL: "http://panel.example:8080", username: "a", password: "b"
            ))
            await app.services.sync.waitForCompletion(playlist.id)
            app.services.syncStatus.set(
                .failed("The provider rejected the username or password."),
                for: playlist.id
            )
            try await render(app, to: "/tmp/panop-live-failed.png")
        }
    }
#endif
