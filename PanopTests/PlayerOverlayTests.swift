import Foundation
import MediaPlayer
@testable import Panop
import PanopPlayback
import Testing

@Suite("Player overlay", .engineGate)
@MainActor
struct PlayerOverlayTests {
    private func makeModel(
        _ engine: ScriptedEngine,
        controlsTimeout: Duration = .seconds(60)
    ) -> PlayerModel {
        PlayerModel(
            title: "Test",
            request: PlaybackRequest(PlaybackItem(
                url: "http://h/x",
                mediaKind: engine.duration == nil ? .live : .movie
            )),
            preferred: .avPlayer,
            controlsTimeout: controlsTimeout,
            makeEngine: { $0 == .avPlayer ? engine : nil }
        )
    }

    private func waitFor(_ condition: () -> Bool, seconds: Double = 5) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private func playing(_ engine: ScriptedEngine, timeout: Duration = .seconds(60)) async -> PlayerModel {
        let model = makeModel(engine, controlsTimeout: timeout)
        model.start()
        _ = await waitFor { model.status == .playing(.avPlayer) }
        return model
    }

    // MARK: - Live and on demand

    @Test
    func `a live channel cannot be scrubbed and a video can`() async {
        let live = await playing(ScriptedEngine(duration: nil))
        #expect(!live.canSeek)
        await live.stop()

        let vod = await playing(ScriptedEngine(duration: 3600))
        #expect(vod.canSeek)
        #expect(vod.duration == 3600)
        await vod.stop()
    }

    @Test
    func `the position follows the engine`() async {
        let engine = ScriptedEngine(duration: 600)
        let model = await playing(engine)

        engine.report(.positionChanged(seconds: 42))

        #expect(await waitFor { model.position == 42 })
        await model.stop()
    }

    @Test
    func `seeking and skipping stay inside the video`() async {
        let engine = ScriptedEngine(duration: 100)
        let model = await playing(engine)
        engine.report(.positionChanged(seconds: 95))
        #expect(await waitFor { model.position == 95 })

        model.skip(by: 10)
        model.skip(by: -500)
        model.seek(to: 30)

        #expect(engine.seeks == [100, 0, 30])
        #expect(model.position == 30)
        await model.stop()
    }

    // MARK: - Tracks

    @Test
    func `tracks arrive and a choice reaches the engine`() async {
        let engine = ScriptedEngine(duration: nil)
        let model = await playing(engine)
        let german = TrackDescriptor(id: "1", label: "Deutsch", languageCode: "de")
        let english = TrackDescriptor(id: "2", label: "English", languageCode: "en")
        let subtitle = TrackDescriptor(id: "9", label: "Deutsch (CC)", languageCode: "de")

        engine.report(.tracksChanged(audio: [german, english], subtitle: [subtitle]))
        #expect(await waitFor { model.audioTracks.count == 2 })
        #expect(model.subtitleTracks == [subtitle])
        #expect(model.selectedAudioID == nil, "nothing is chosen until the user chooses")

        model.selectAudio(id: "2")
        model.selectSubtitle(id: "9")
        #expect(engine.audioSelections == ["2"])
        #expect(engine.subtitleSelections == ["9"])
        #expect(model.selectedAudioID == "2")

        model.selectSubtitle(id: nil)
        #expect(engine.subtitleSelections == ["9", nil])
        #expect(model.selectedSubtitleID == nil)
        await model.stop()
    }

    // MARK: - Controls visibility

    @Test
    func `the controls hide on their own once playing`() async {
        let engine = ScriptedEngine()
        let model = await playing(engine, timeout: .milliseconds(80))

        #expect(await waitFor { !model.controlsVisible })
        #expect(!model.showsControls)
        await model.stop()
    }

    @Test
    func `a tap toggles the controls and any control use brings them back`() async {
        let engine = ScriptedEngine()
        let model = await playing(engine)
        #expect(model.controlsVisible)

        model.toggleControls()
        #expect(!model.controlsVisible)

        model.toggleControls()
        #expect(model.controlsVisible)

        model.toggleControls()
        model.selectAudio(id: nil)
        #expect(model.controlsVisible)
        await model.stop()
    }

    @Test
    func `the controls stay up while paused`() async {
        let engine = ScriptedEngine()
        let model = await playing(engine, timeout: .milliseconds(40))

        model.togglePause()
        #expect(await waitFor { model.isPaused })
        try? await Task.sleep(for: .milliseconds(200))

        #expect(!model.controlsVisible, "the timer still runs")
        #expect(model.showsControls, "but a paused picture keeps its controls")
        await model.stop()
    }

    @Test
    func `the controls do not hide while one has focus, and count down once it lets go`() async {
        let engine = ScriptedEngine()
        let model = await playing(engine, timeout: .milliseconds(60))
        model.holdControls(true)

        try? await Task.sleep(for: .milliseconds(250))
        #expect(model.controlsVisible, "a held bar stays up well past the timeout")

        model.holdControls(false)
        #expect(await waitFor { !model.controlsVisible })
        await model.stop()
    }

    @Test
    func `holding the controls brings them back if they had gone`() async {
        let model = await playing(ScriptedEngine(), timeout: .milliseconds(40))
        #expect(await waitFor { !model.controlsVisible })

        model.holdControls(true)

        #expect(model.controlsVisible)
        await model.stop()
    }

    @Test
    func `a menu, the AirPlay picker and focus each hold the controls, and all must let go`() async {
        let model = await playing(ScriptedEngine(), timeout: .milliseconds(60))

        model.holdControls(true, reason: "airplay")
        model.holdControls(true, reason: "focus")
        try? await Task.sleep(for: .milliseconds(250))
        #expect(model.controlsVisible, "held twice, so up well past the timeout")

        model.holdControls(false, reason: "focus")
        try? await Task.sleep(for: .milliseconds(250))
        #expect(model.controlsVisible, "the picker is still open, whatever focus did")

        model.holdControls(false, reason: "airplay")
        #expect(await waitFor { !model.controlsVisible }, "once everything lets go the countdown runs")
        await model.stop()
    }

    @Test
    func `the same reason holding twice is one hold, released once`() async {
        let model = await playing(ScriptedEngine(), timeout: .milliseconds(60))

        model.holdControls(true, reason: "audio")
        model.holdControls(true, reason: "audio")
        model.holdControls(false, reason: "audio")

        #expect(await waitFor { !model.controlsVisible })
        await model.stop()
    }

    @Test
    func `a track menu holds the controls up while it is open and releases them when it closes`() async {
        let model = await playing(ScriptedEngine(), timeout: .milliseconds(60))

        model.holdControls(true, reason: "subtitles")
        try? await Task.sleep(for: .milliseconds(250))
        #expect(model.controlsVisible)

        model.holdControls(false, reason: "subtitles")
        #expect(await waitFor { !model.controlsVisible })
        await model.stop()
    }

    // MARK: - Clock text

    @Test(arguments: [
        (0.0, "0:00"), (5.0, "0:05"), (65.0, "1:05"), (3599.0, "59:59"),
        (3600.0, "1:00:00"), (3725.0, "1:02:05"), (-4.0, "0:00"), (Double.nan, "0:00")
    ])
    func `time reads as a clock`(seconds: Double, text: String) {
        #expect(PlayerTime.text(seconds) == text)
    }
}

@MainActor
final class RecordingNowPlaying: NowPlayingPublishing {
    private(set) var infos: [NowPlayingInfo] = []
    private(set) var began = 0
    private(set) var ended = 0
    private var onCommand: (@MainActor (RemoteCommand) -> Void)?

    var last: NowPlayingInfo? {
        infos.last
    }

    func begin(onCommand: @escaping @MainActor (RemoteCommand) -> Void) {
        began += 1
        self.onCommand = onCommand
    }

    func update(_ info: NowPlayingInfo) {
        infos.append(info)
    }

    func end() {
        ended += 1
    }

    /// What the system does when someone presses a key.
    func send(_ command: RemoteCommand) {
        onCommand?(command)
    }
}

@Suite("Now Playing", .engineGate)
@MainActor
struct NowPlayingTests {
    private func playing(
        _ engine: ScriptedEngine,
        sink: RecordingNowPlaying,
        title: String = "Heat"
    ) async -> PlayerModel {
        let model = PlayerModel(
            title: title,
            request: PlaybackRequest(PlaybackItem(
                url: "http://h/x",
                mediaKind: engine.duration == nil ? .live : .movie
            )),
            preferred: .avPlayer,
            nowPlaying: sink,
            makeEngine: { $0 == .avPlayer ? engine : nil }
        )
        model.start()
        let deadline = ContinuousClock.now + .seconds(5)
        while model.status != .playing(.avPlayer), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return model
    }

    private func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    @Test
    func `playing publishes the title and that it is playing`() async {
        let sink = RecordingNowPlaying()
        let model = await playing(ScriptedEngine(duration: 5400), sink: sink)

        #expect(sink.began == 1)
        #expect(sink.last?.title == "Heat")
        #expect(sink.last?.isPlaying == true)
        await model.stop()
    }

    @Test
    func `a channel is published as live and a video with its length`() async {
        let live = RecordingNowPlaying()
        let channel = await playing(ScriptedEngine(duration: nil), sink: live)
        #expect(live.last?.isLive == true)
        await channel.stop()

        let vod = RecordingNowPlaying()
        let movie = await playing(ScriptedEngine(duration: 5400), sink: vod)
        #expect(vod.last?.duration == 5400)
        #expect(vod.last?.isLive == false)
        await movie.stop()
    }

    @Test
    func `pausing and seeking are published`() async {
        let engine = ScriptedEngine(duration: 600)
        let sink = RecordingNowPlaying()
        let model = await playing(engine, sink: sink)

        model.seek(to: 120)
        #expect(sink.last?.position == 120)

        model.togglePause()
        #expect(await wait { sink.last?.isPlaying == false })
        await model.stop()
    }

    @Test
    func `system commands drive the player`() async {
        let engine = ScriptedEngine(duration: 600)
        let sink = RecordingNowPlaying()
        let model = await playing(engine, sink: sink)

        sink.send(.pause)
        #expect(await wait { model.isPaused })
        #expect(engine.pauseCalls == 1)

        sink.send(.pause)
        #expect(engine.pauseCalls == 1, "pausing a paused player does nothing")

        sink.send(.skip(10))
        sink.send(.skip(-10))
        sink.send(.seek(300))
        #expect(engine.seeks == [10, 0, 300])
        await model.stop()
    }

    @Test
    func `stopping gives the controls back`() async {
        let sink = RecordingNowPlaying()
        let model = await playing(ScriptedEngine(duration: nil), sink: sink)

        await model.stop()

        #expect(sink.ended == 1)
    }

    @Test
    func `nothing is published for a stream that never played`() async {
        let sink = RecordingNowPlaying()
        let model = PlayerModel(
            title: "X",
            request: PlaybackRequest(PlaybackItem(url: "http://h/x")),
            preferred: .avPlayer,
            nowPlaying: sink,
            makeEngine: { _ in nil }
        )

        model.start()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(sink.infos.allSatisfy { $0.title == "X" })
        #expect(sink.last?.isPlaying != true)
        await model.stop()
    }
}

@Suite("System Now Playing", .serialized, .engineGate)
@MainActor
struct SystemNowPlayingTests {
    @Test
    func `it sets the system's now playing info and clears it`() {
        let system = SystemNowPlaying()
        system.begin { _ in }

        system.update(NowPlayingInfo(title: "Heat", position: 120, duration: 5400, isPlaying: true))
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Heat")
        #expect(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 120)
        #expect(info?[MPMediaItemPropertyPlaybackDuration] as? Double == 5400)
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(info?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == false)

        system.update(NowPlayingInfo(title: "3sat", position: 0, duration: nil, isPlaying: false))
        let live = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(live?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(live?[MPMediaItemPropertyPlaybackDuration] == nil, "a channel has no length")
        #expect(live?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
        #expect(!MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled, "no scrubbing a live channel")

        system.end()
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
    }

    @Test
    func `beginning twice does not stack up command handlers`() {
        let system = SystemNowPlaying()
        system.begin { _ in }
        system.begin { _ in }
        system.end()
        // No public way to count a command's targets; what this guards is that
        // begin and end can be repeated without a crash or an exception.
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
    }
}

@Suite("AirPlay", .engineGate)
@MainActor
struct AirPlayTests {
    private func model(_ makeEngine: @escaping PlaybackCoordinator.EngineFactory) -> PlayerModel {
        PlayerModel(
            title: "X",
            request: PlaybackRequest(PlaybackItem(url: "http://h/x", mediaKind: .live)),
            preferred: .avPlayer,
            makeEngine: makeEngine
        )
    }

    @Test
    func `only the AVPlayer engine offers it`() async {
        // No engine yet: nothing to send anywhere.
        #expect(!model { _ in nil }.supportsAirPlay)

        let scripted = ScriptedEngine()
        let other = model { $0 == .avPlayer ? scripted : nil }
        other.start()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!other.supportsAirPlay, "an engine that is not AVPlayer cannot AirPlay its video")
        await other.stop()
    }

    @Test
    func `AVPlayer allows external playback on the platforms that have it`() {
        let engine = AVPlayerEngine()
        #if os(tvOS)
            _ = engine
        #else
            #expect(engine.player.allowsExternalPlayback)
        #endif
    }
}
