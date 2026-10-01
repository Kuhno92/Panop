import Foundation
import PanopCore
import PanopPlayback

/// A deterministic app for the UI tests, selected by the launch argument `-panop-uitest`.
///
/// In-memory storage, one seeded playlist, and an engine that plays instantly, so a UI test
/// can drive the real screens without a network, a provider or a stream. Debug builds only:
/// none of it exists in a Release build, and `isActive` is then always false.
enum UITestMode {
    #if DEBUG
        static let isActive = ProcessInfo.processInfo.arguments.contains("-panop-uitest")

        /// How long the player's controls stay up, set by the test through the environment
        /// `PANOP_CONTROLS_TIMEOUT` (seconds). The real four seconds is shorter than a UI test
        /// takes to look at the screen, so tests default to long and the one test that is about
        /// hiding asks for short.
        static var controlsTimeout: Duration? {
            guard isActive, let text = ProcessInfo.processInfo.environment["PANOP_CONTROLS_TIMEOUT"],
                  let seconds = Double(text) else { return nil }
            return .seconds(seconds)
        }
    #else
        static let isActive = false
        static var controlsTimeout: Duration? {
            nil
        }
    #endif
}

#if DEBUG
    extension UITestMode {
        /// Channel names the tests look for. The first three are real-looking on purpose, so a
        /// search has something distinct to match.
        static let channelNames = ["Das Erste", "ZDF", "3sat", "Arte", "Phoenix", "Tagesschau 24"]
            + (7 ... 30).map { "Channel \($0)" }

        static func seed(_ services: AppServices) async {
            let lines = channelNames.enumerated().map { index, name in
                "#EXTINF:-1 tvg-id=\"c\(index)\" group-title=\"\(index < 6 ? "Germany" : "Other")\",\(name)\n" +
                    "http://127.0.0.1:9/live/\(index).ts"
            }
            let text = "#EXTM3U\n" + lines.joined(separator: "\n") + "\n"
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(UUID().uuidString).m3u")
            do {
                try text.write(to: file, atomically: true, encoding: .utf8)
                _ = try await services.library.add(.m3uFile(name: "Test Source", fileURL: file))
            } catch {
                assertionFailure("UI test seed failed: \(error)")
            }
        }
    }

    /// An engine that is "playing" as soon as it is told to, with two audio tracks and one
    /// subtitle track, and no picture. Stands in for a real stream in UI tests.
    @MainActor
    final class UITestEngine: PlaybackEngine {
        static var kind: PlaybackEngineKind {
            .avPlayer
        }

        let events: AsyncStream<PlaybackEvent>
        private let output: AsyncStream<PlaybackEvent>.Continuation
        private(set) var state = PlaybackState.idle
        private(set) var position: Double? = 0
        private(set) var duration: Double?
        private(set) var audioTracks = [
            TrackDescriptor(id: "1", label: "Deutsch", languageCode: "de"),
            TrackDescriptor(id: "2", label: "English", languageCode: "en")
        ]
        private(set) var subtitleTracks = [TrackDescriptor(id: "9", label: "Deutsch (CC)", languageCode: "de")]
        private var ticker: Task<Void, Never>?

        init() {
            (events, output) = AsyncStream.makeStream()
        }

        func load(_ item: PlaybackItem) async throws {
            duration = item.mediaKind == .live ? nil : 5400
            state = .opening
        }

        func play() {
            state = .playing
            output.yield(.stateChanged(.playing))
            output.yield(.tracksChanged(audio: audioTracks, subtitle: subtitleTracks))
            ticker?.cancel()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, state == .playing else { continue }
                    position = (position ?? 0) + 1
                    output.yield(.positionChanged(seconds: position ?? 0))
                }
            }
        }

        func pause() {
            state = .paused
            output.yield(.stateChanged(.paused))
        }

        func seek(to seconds: Double) {
            position = seconds
        }

        func selectAudioTrack(id: String?) {}
        func selectSubtitleTrack(id: String?) {}

        func stop() async {
            ticker?.cancel()
            output.finish()
        }
    }
#endif
