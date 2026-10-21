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

    private let relayEndpoint = ProxyEndpoint(
        socksPort: 1080, httpPort: 8080, username: "u", password: "p", relayPort: 9000, relaySecret: "abc123"
    )

    @Test
    func `an engine that cannot take a proxy is given the relay's address, not the real one`() async throws {
        let factory = EngineFactory([:])
        let coordinator = PlaybackCoordinator(
            priority: [.avPlayer],
            makeEngine: { factory.make($0) },
            proxy: { relayEndpoint }
        )
        coordinator.play(stream)
        let log = EventLog(coordinator)
        #expect(await log.waitForStatus(.playing(.avPlayer)))
        let item = try #require(factory.created.first?.engine.loadedItems.first)
        #expect(item.url == relayEndpoint.relayURL(for: "http://host/live/1.ts"))
        #expect(item.url.hasPrefix("http://127.0.0.1:9000/abc123/"))
        #expect(item.proxy == nil)
    }

    @Test
    func `an engine that takes a proxy still gets the real address and the proxy`() async throws {
        let factory = EngineFactory([:])
        let coordinator = PlaybackCoordinator(
            priority: [.lumeEngine],
            makeEngine: { factory.make($0) },
            proxy: { relayEndpoint }
        )
        coordinator.play(stream)
        let log = EventLog(coordinator)
        #expect(await log.waitForStatus(.playing(.lumeEngine)))
        let item = try #require(factory.created.first?.engine.loadedItems.first)
        #expect(item.url == "http://host/live/1.ts")
        #expect(item.proxy == relayEndpoint)
    }

    @Test
    func `with no relay, an engine that cannot take a proxy is given nothing rather than the real address`(
    ) async throws {
        let factory = EngineFactory([:])
        let coordinator = PlaybackCoordinator(
            priority: [.avPlayer],
            makeEngine: { factory.make($0) },
            proxy: { endpoint }
        )
        coordinator.play(stream)
        let log = EventLog(coordinator)
        #expect(await log.waitForStatus(.playing(.avPlayer)))
        #expect(try #require(factory.created.first?.engine.loadedItems.first).url.isEmpty)
    }
}
