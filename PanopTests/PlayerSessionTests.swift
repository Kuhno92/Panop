import Foundation
@testable import Panop
import PanopPlayback
import Testing

@Suite("Progress reporting")
@MainActor
struct ProgressReportingTests {
    /// What the player told whoever keeps resume points.
    private final class Reports {
        var all: [(position: Double, duration: Double?)] = []
    }

    private func makeModel(_ engine: ScriptedEngine, reports: Reports, startPosition: Double = 0) -> PlayerModel {
        PlayerModel(
            title: "Film",
            request: PlaybackRequest(PlaybackItem(
                url: "http://h/x",
                mediaKind: engine.duration == nil ? .live : .movie
            )),
            preferred: .avPlayer,
            startPosition: startPosition,
            onProgress: { reports.all.append(($0, $1)) },
            makeEngine: { $0 == .avPlayer ? engine : nil }
        )
    }

    private func settle(_ model: PlayerModel) async {
        model.start()
        let deadline = ContinuousClock.now + .seconds(5)
        while model.status != .playing(.avPlayer), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func wait(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test
    func `progress is handed on every fifteen seconds, not every tick`() async {
        let engine = ScriptedEngine(duration: 600)
        let reports = Reports()
        let model = makeModel(engine, reports: reports)
        await settle(model)

        for second in [3.0, 8.0, 14.0, 16.0, 20.0, 29.0, 31.0] {
            engine.report(.positionChanged(seconds: second))
            await wait { model.position == second }
        }

        #expect(reports.all.map(\.position) == [16, 31], "only a position fifteen seconds past the last report")
        #expect(reports.all.allSatisfy { $0.duration == 600 })
        await model.stop()
    }

    @Test
    func `where it was left is reported once more when it stops`() async {
        let engine = ScriptedEngine(duration: 600)
        let reports = Reports()
        let model = makeModel(engine, reports: reports)
        await settle(model)
        engine.report(.positionChanged(seconds: 7))
        await wait { model.position == 7 }

        await model.stop()

        #expect(reports.all.map(\.position) == [7])
    }

    @Test
    func `a live channel never reports progress`() async {
        let engine = ScriptedEngine(duration: nil)
        let reports = Reports()
        let model = makeModel(engine, reports: reports)
        await settle(model)

        engine.report(.positionChanged(seconds: 120))
        await wait { model.position == 120 }
        await model.stop()

        #expect(reports.all.isEmpty)
    }

    @Test
    func `a resumed film counts fifteen seconds from where it began`() async {
        let engine = ScriptedEngine(duration: 7200)
        let reports = Reports()
        let model = makeModel(engine, reports: reports, startPosition: 3000)
        await settle(model)

        engine.report(.positionChanged(seconds: 3004))
        await wait { model.position == 3004 }
        #expect(reports.all.isEmpty, "four seconds in is not a report")

        engine.report(.positionChanged(seconds: 3020))
        await wait { model.position == 3020 }
        #expect(reports.all.map(\.position) == [3020])
        await model.stop()
    }
}

@MainActor
private final class FakeMemory: EngineMemory {
    var engines: [String: PlaybackEngineKind] = [:]

    func remembered(for key: String) -> PlaybackEngineKind? {
        engines[key]
    }

    func remember(_ engine: PlaybackEngineKind, for key: String) {
        engines[key] = engine
    }

    func forget(for key: String) {
        engines[key] = nil
    }
}

@Suite("Engine memory")
@MainActor
struct EngineMemoryTests {
    /// Engines by kind, recording which were asked for, in order.
    private final class Factory {
        var asked: [PlaybackEngineKind] = []
        var engines: [PlaybackEngineKind: ScriptedEngine]

        init(_ engines: [PlaybackEngineKind: ScriptedEngine]) {
            self.engines = engines
        }

        func make(_ kind: PlaybackEngineKind) -> (any PlaybackEngine)? {
            asked.append(kind)
            return engines[kind]
        }
    }

    private func model(_ factory: Factory, memory: FakeMemory) -> PlayerModel {
        PlayerModel(
            title: "Channel",
            request: PlaybackRequest(PlaybackItem(url: "http://h/x.ts", mediaKind: .live)),
            preferred: .avPlayer,
            memory: memory,
            memoryKey: "p|c",
            makeEngine: { factory.make($0) }
        )
    }

    private func playing(_ model: PlayerModel, _ kind: PlaybackEngineKind) async -> Bool {
        model.start()
        let deadline = ContinuousClock.now + .seconds(5)
        while model.status != .playing(kind), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return model.status == .playing(kind)
    }

    private func unreadable() -> ScriptedEngine {
        let engine = ScriptedEngine()
        engine.loadError = PlaybackError(code: .unsupportedFormat)
        return engine
    }

    @Test
    func `an engine that played after the first choice failed is remembered`() async {
        let memory = FakeMemory()
        let factory = Factory([.avPlayer: unreadable(), .vlcKit: ScriptedEngine()])
        let model = model(factory, memory: memory)

        #expect(await playing(model, .vlcKit))

        #expect(memory.engines["p|c"] == .vlcKit)
        await model.stop()
    }

    @Test
    func `next time the remembered engine goes first and the failing one is not tried`() async {
        let memory = FakeMemory()
        memory.engines["p|c"] = .vlcKit
        let factory = Factory([.avPlayer: unreadable(), .vlcKit: ScriptedEngine()])
        let model = model(factory, memory: memory)

        #expect(await playing(model, .vlcKit))

        #expect(factory.asked.first == .vlcKit)
        #expect(!factory.asked.contains(.avPlayer), "AVPlayer was tried again for a channel it cannot read")
        await model.stop()
    }

    @Test
    func `the person's own choice playing it again clears the memory`() async {
        let memory = FakeMemory()
        memory.engines["p|c"] = .vlcKit
        // VLC no longer opens it, and AVPlayer (the setting) now does.
        let factory = Factory([.vlcKit: unreadable(), .avPlayer: ScriptedEngine()])
        let model = model(factory, memory: memory)

        #expect(await playing(model, .avPlayer))

        #expect(memory.engines["p|c"] == nil, "a memory that no longer holds should go")
        await model.stop()
    }

    @Test
    func `a channel that plays on the first choice remembers nothing`() async {
        let memory = FakeMemory()
        let factory = Factory([.avPlayer: ScriptedEngine()])
        let model = model(factory, memory: memory)

        #expect(await playing(model, .avPlayer))

        #expect(memory.engines.isEmpty)
        await model.stop()
    }
}
