import Foundation
@testable import Panop
import PanopPlayback
import Testing

@Suite("Player overlay")
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

    // MARK: - Clock text

    @Test(arguments: [
        (0.0, "0:00"), (5.0, "0:05"), (65.0, "1:05"), (3599.0, "59:59"),
        (3600.0, "1:00:00"), (3725.0, "1:02:05"), (-4.0, "0:00"), (Double.nan, "0:00")
    ])
    func `time reads as a clock`(seconds: Double, text: String) {
        #expect(PlayerTime.text(seconds) == text)
    }
}
