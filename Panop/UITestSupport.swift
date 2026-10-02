import Foundation
import PanopCore
import PanopEPG
import PanopPlayback
#if canImport(UIKit)
    import UIKit
#endif

/// A deterministic app for the UI tests, selected by the launch argument `-panop-uitest`.
///
/// In-memory storage, one seeded playlist, and an engine that plays instantly, so a UI test
/// can drive the real screens without a network, a provider or a stream. Debug builds only:
/// none of it exists in a Release build, and `isActive` is then always false.
enum UITestMode {
    #if DEBUG
        static let isActive = ProcessInfo.processInfo.arguments.contains("-panop-uitest")

        /// A UI test waits for every animation to settle before it looks at the screen, so
        /// removing them makes each step shorter without changing what is being checked.
        static func disableAnimations() {
            #if canImport(UIKit)
                UIView.setAnimationsEnabled(false)
            #endif
        }

        /// How long the player's controls stay up, set by the test through the environment
        /// `PANOP_CONTROLS_TIMEOUT` (seconds). The real four seconds is shorter than a UI test
        /// takes to look at the screen, so tests default to long and the one test that is about
        /// hiding asks for short.
        static var controlsTimeout: Duration? {
            guard isActive, let text = ProcessInfo.processInfo.environment["PANOP_CONTROLS_TIMEOUT"],
                  let seconds = Double(text) else { return nil }
            return .seconds(seconds)
        }

        /// Open a player window for the first seeded channel at launch (macOS), so the window can be
        /// seen working without a way to click. `-panop-open-player-window`.
        static let opensPlayerWindow = isActive && ProcessInfo.processInfo.arguments
            .contains("-panop-open-player-window")

        /// The tab to open on, from the environment `PANOP_START_TAB` (`home`, `live`). Most UI
        /// tests are about Live TV and ask for it; the home screen tests ask for `home`.
        static var startTab: AppTab? {
            guard isActive else { return nil }
            switch ProcessInfo.processInfo.environment["PANOP_START_TAB"] {
            case "home": return .home
            case "live": return .live
            case "movies": return .movies
            case "series": return .series
            case "settings": return .settings
            default: return nil
            }
        }
    #else
        static let isActive = false
        static let opensPlayerWindow = false
        static var controlsTimeout: Duration? {
            nil
        }

        static var startTab: AppTab? {
            nil
        }
    #endif
}

#if DEBUG
    extension UITestMode {
        /// The simulator keeps UserDefaults between launches, and Live TV remembers its filters.
        /// A test that left it on Favourites must not decide what the next one sees.
        static func resetPreferences() {
            for key in [
                "liveListMode", "liveSourceFilter", "liveSortOrder", "playbackEngine",
                StartupPreference.actionKey, StartupPreference.channelKey, StartupPreference.channelNameKey
            ] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        /// Channel names the tests look for. The first three are real-looking on purpose, so a
        /// search has something distinct to match.
        static let channelNames = ["Das Erste", "ZDF", "3sat", "Arte", "Phoenix", "Tagesschau 24"]
            + (7 ... 30).map { "Channel \($0)" }

        /// Films and series for the Movies and Series screens. The address path is what marks them.
        static let movieNames = ["Alien", "Blade Runner", "Casablanca", "Dune", "Eraser", "Fargo"]
        static let seriesNames = ["Dark S01E01", "Dark S01E02", "Severance S01E01"]

        /// A real provider to try the app against, from the environment `PANOP_DEV_XTREAM` as
        /// `url|username|password`. Debug builds only, held in memory only, and never written to a
        /// file: the login is the developer's own and stays out of the repository.
        static func seedDevProvider(_ services: AppServices) async -> Bool {
            let parts = (ProcessInfo.processInfo.environment["PANOP_DEV_XTREAM"] ?? "").split(separator: "|")
                .map(String.init)
            guard parts.count == 3 else { return false }
            do {
                _ = try await services.library.add(.xtream(
                    name: "Dev",
                    baseURL: parts[0],
                    username: parts[1],
                    password: parts[2]
                ))
                return true
            } catch {
                assertionFailure("dev provider seed failed: \(error)")
                return false
            }
        }

        static func seed(_ services: AppServices) async {
            if await seedDevProvider(services) {
                return
            }
            var lines = channelNames.enumerated().map { index, name in
                "#EXTINF:-1 tvg-id=\"c\(index)\" group-title=\"\(index < 6 ? "Germany" : "Other")\",\(name)\n" +
                    "http://127.0.0.1:9/live/\(index).ts"
            }
            lines += movieNames.enumerated().map { index, name in
                "#EXTINF:5400 tvg-id=\"m\(index)\" group-title=\"\(index < 3 ? "Films" : "Classics")\",\(name)\nhttp://127.0.0.1:9/movie/u/p/\(index).mp4"
            }
            lines += seriesNames.enumerated().map { index, name in
                "#EXTINF:2700 tvg-id=\"s\(index)\" group-title=\"Shows\",\(name)\nhttp://127.0.0.1:9/series/u/p/\(index).mkv"
            }
            let text = "#EXTM3U\n" + lines.joined(separator: "\n") + "\n"
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(UUID().uuidString).m3u")
            do {
                try text.write(to: file, atomically: true, encoding: .utf8)
                let liveOnly = ProcessInfo.processInfo.environment["PANOP_LIVE_ONLY"] == "1"
                let playlist = try await services.library.add(
                    .m3uFile(name: "Test Source", fileURL: file),
                    includeVOD: !liveOnly
                )
                // A guide for 3sat (the third channel, `c2`), so its row can say what is on.
                let now = Date.now
                _ = try await services.catalogStore.upsertProgrammes([
                    EPGProgramme(
                        channelID: "c2",
                        start: now.addingTimeInterval(-1800),
                        stop: now.addingTimeInterval(1800),
                        title: "Seeded News"
                    ),
                    EPGProgramme(
                        channelID: "c2",
                        start: now.addingTimeInterval(1800),
                        stop: now.addingTimeInterval(7200),
                        title: "Seeded Film"
                    )
                ], playlist: playlist.id)
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
            // Where it was asked to start, so a resume can be seen to have worked.
            position = item.startPosition ?? 0
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
