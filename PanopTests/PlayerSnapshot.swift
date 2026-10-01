#if os(macOS)
    import Foundation
    @testable import Panop
    import PanopCore
    import PanopPlayback
    import SwiftUI
    import Testing

    /// Renders the player overlay to /tmp/panop-player-*.png so a person can look at it.
    /// Not an assertion about pixels. Off unless `PANOP_SNAPSHOT=1`, as for the playlists.
    @Suite("Player snapshot", .enabled(if: ProcessInfo.processInfo.environment["PANOP_SNAPSHOT"] == "1"))
    @MainActor
    struct PlayerSnapshot {
        private let tracks = (
            audio: [
                TrackDescriptor(id: "1", label: "Deutsch", languageCode: "de"),
                TrackDescriptor(id: "2", label: "English", languageCode: "en")
            ],
            subtitle: [TrackDescriptor(id: "9", label: "Deutsch (CC)", languageCode: "de")]
        )

        @Test
        func `a movie`() async throws {
            let engine = ScriptedEngine(duration: 5400)
            let model = try await playing(engine, title: "Heat (1995)", kind: .movie)
            engine.report(.tracksChanged(audio: tracks.audio, subtitle: tracks.subtitle))
            engine.report(.positionChanged(seconds: 1834))
            try await Task.sleep(for: .milliseconds(100))
            try await snapshot(model, to: "/tmp/panop-player-movie.png")
            await model.stop()
        }

        @Test
        func `a live channel`() async throws {
            let engine = ScriptedEngine(duration: nil)
            let model = try await playing(engine, title: "3sat", kind: .live)
            engine.report(.tracksChanged(audio: tracks.audio, subtitle: []))
            try await Task.sleep(for: .milliseconds(100))
            try await snapshot(model, to: "/tmp/panop-player-live.png")
            await model.stop()
        }

        @Test
        func `a paused movie`() async throws {
            let engine = ScriptedEngine(duration: 5400)
            let model = try await playing(engine, title: "Heat (1995)", kind: .movie)
            engine.report(.positionChanged(seconds: 4000))
            model.togglePause()
            try await Task.sleep(for: .milliseconds(100))
            try await snapshot(model, to: "/tmp/panop-player-paused.png")
            await model.stop()
        }

        private func playing(_ engine: ScriptedEngine, title: String, kind: MediaKind) async throws -> PlayerModel {
            let model = PlayerModel(
                title: title,
                request: PlaybackRequest(PlaybackItem(url: "http://h/x", mediaKind: kind)),
                preferred: .avPlayer,
                makeEngine: { $0 == .avPlayer ? engine : nil }
            )
            model.start()
            try await Task.sleep(for: .milliseconds(300))
            return model
        }

        private func snapshot(_ model: PlayerModel, to path: String) async throws {
            let view = PlayerView(model: model)
                .frame(width: 900, height: 506)
                .background(LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom))
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 506)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(800))
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
            window.close()
        }
    }
#endif
