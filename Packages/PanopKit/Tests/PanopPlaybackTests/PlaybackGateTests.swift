import Foundation
import PanopCore
@testable import PanopPlayback
import Testing

@Suite("Playback gate", .serialized)
@MainActor
struct PlaybackGateTests {
    private let stream = PlaybackRequest(PlaybackItem(url: "http://host/live/1.ts", mediaKind: .live))

    @Test
    func `a blocked network fails the stream without opening any engine`() async {
        let factory = EngineFactory([:])
        let coordinator = PlaybackCoordinator(
            priority: [.avPlayer, .vlcKit],
            makeEngine: { factory.make($0) },
            gate: { .vpnRequired }
        )
        let log = EventLog(coordinator)

        coordinator.play(stream)

        let failed = await log.wait {
            if case .status(.failed) = $0 {
                true
            } else {
                false
            }
        }
        #expect(failed != nil)
        guard case let .failed(failure) = coordinator.status else {
            Issue.record("expected a failure, got \(coordinator.status)")
            return
        }
        #expect(failure.lastError?.message == NetworkBlock.vpnRequired.description)
        #expect(factory.created.isEmpty)
    }

    private let endpoint = ProxyEndpoint(socksPort: 1080, httpPort: 8080, username: "u", password: "p")

    @Test
    func `with the tunnel on, an internet stream carries the proxy to the engine`() async {
        let factory = EngineFactory([:])
        let coordinator = PlaybackCoordinator(
            priority: [.lumeEngine],
            makeEngine: { factory.make($0) },
            proxy: { endpoint }
        )
        coordinator.play(stream)
        let log = EventLog(coordinator)
        #expect(await log.waitForStatus(.playing(.lumeEngine)))
        #expect(factory.created.first?.engine.loadedItems.first?.proxy == endpoint)
    }

    @Test
    func `a local address gets no proxy`() async {
        let factory = EngineFactory([:])
        let coordinator = PlaybackCoordinator(
            priority: [.lumeEngine],
            makeEngine: { factory.make($0) },
            proxy: { endpoint }
        )
        coordinator.play(PlaybackRequest(PlaybackItem(url: "http://127.0.0.1:9000/a.ts", mediaKind: .live)))
        let log = EventLog(coordinator)
        #expect(await log.waitForStatus(.playing(.lumeEngine)))
        #expect(factory.created.first?.engine.loadedItems.first?.proxy == nil)
    }

    @Test
    func `AVPlayer is skipped while the tunnel is on, and the next engine plays`() async {
        let factory = EngineFactory([:])
        let coordinator = PlaybackCoordinator(
            priority: [.avPlayer, .lumeEngine],
            makeEngine: { factory.make($0) },
            proxy: { endpoint }
        )
        coordinator.play(stream)
        let log = EventLog(coordinator)
        #expect(await log.waitForStatus(.playing(.lumeEngine)))
        #expect(!factory.created.contains { $0.kind == .avPlayer })
    }

    @Test
    func `if only AVPlayer is left, the stream fails rather than connecting directly`() async {
        let factory = EngineFactory([:])
        let coordinator = PlaybackCoordinator(
            priority: [.avPlayer],
            makeEngine: { factory.make($0) },
            proxy: { endpoint }
        )
        coordinator.play(stream)
        let log = EventLog(coordinator)
        #expect(await log.wait {
            if case .status(.failed) = $0 {
                true
            } else {
                false
            }
        } != nil)
        #expect(factory.created.isEmpty)
    }
}
