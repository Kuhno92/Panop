import Foundation
@testable import Panop
import PanopPlayback

/// An engine the test drives by hand, for the parts of the player that are about what an
/// engine reports rather than about any real media framework.
@MainActor
final class ScriptedEngine: PlaybackEngine {
    static var kind: PlaybackEngineKind {
        .avPlayer
    }

    let events: AsyncStream<PlaybackEvent>
    private let output: AsyncStream<PlaybackEvent>.Continuation

    private(set) var state = PlaybackState.idle
    var position: Double?
    var duration: Double?
    var audioTracks: [TrackDescriptor] = []
    var subtitleTracks: [TrackDescriptor] = []

    private(set) var seeks: [Double] = []
    private(set) var audioSelections: [String?] = []
    private(set) var subtitleSelections: [String?] = []
    private(set) var pauseCalls = 0

    init(duration: Double? = nil) {
        self.duration = duration
        (events, output) = AsyncStream.makeStream()
    }

    func report(_ event: PlaybackEvent) {
        output.yield(event)
    }

    /// When set, `load` fails with it, as an engine that cannot open the stream does.
    var loadError: PlaybackError?

    func load(_ item: PlaybackItem) async throws {
        if let loadError {
            throw loadError
        }
    }

    func play() {
        state = .playing
        output.yield(.stateChanged(.playing))
    }

    func pause() {
        pauseCalls += 1
        state = .paused
        output.yield(.stateChanged(.paused))
    }

    func seek(to seconds: Double) {
        seeks.append(seconds)
    }

    func selectAudioTrack(id: String?) {
        audioSelections.append(id)
    }

    func selectSubtitleTrack(id: String?) {
        subtitleSelections.append(id)
    }

    func stop() async {
        output.finish()
    }
}
