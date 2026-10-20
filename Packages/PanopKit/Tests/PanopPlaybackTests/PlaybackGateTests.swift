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
}
