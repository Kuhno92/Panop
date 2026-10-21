import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

/// Plays a real public stream through the real tunnel, with a real WireGuard file, and checks the tunnel's own
/// byte counters rise. Off unless a file is named:
///
///     TEST_RUNNER_PANOP_WG_CONF=$PWD/.secrets/NL-FREE-104.conf PANOP_ONLY=RealTunnelPlaybackTests Scripts/test-app.sh
/// macos
@Suite(
    "A stream really goes through the tunnel",
    .enabled(if: ProcessInfo.processInfo.environment["PANOP_WG_CONF"] != nil),
    .serialized,
    .engineGate
)
@MainActor
struct RealTunnelPlaybackTests {
    private static let stream = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"

    private func run(_ kind: PlaybackEngineKind) async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PANOP_WG_CONF"])
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let backend = GoTunnelBackend()
        let endpoint = try backend.start(config: text)
        defer { backend.stop() }
        try backend.waitReady(seconds: 20)

        let network = ProviderNetwork()
        network.setRoute(.tunnel(endpoint))
        let before = backend.counters.received

        let coordinator = PlaybackCoordinator(
            priority: [kind],
            makeEngine: { EngineRegistry.make($0) },
            gate: { network.block },
            proxy: { network.proxy }
        )
        coordinator.play(PlaybackRequest(PlaybackItem(url: Self.stream, mediaKind: .live)))
        var playing = false
        for _ in 0 ..< 400 {
            if case .playing = coordinator.status {
                playing = true
                break
            }
            if case .failed = coordinator.status {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .seconds(3))
        let early = backend.counters.received - before
        try? await Task.sleep(for: .seconds(10))
        let after = backend.counters.received
        let info = coordinator.activeEngine?.streamInfo.flatMap(StreamInfoText.summary) ?? "none"
        let line = "\(kind): \(early) bytes after 3 s, \(after - before) after 13 s, info: \(info)\n"
        try? line.appendLine(to: "/tmp/real-tunnel.txt")
        await coordinator.stop()

        #expect(playing, "\(kind) never played: \(coordinator.status)")
        #expect(
            after - before > 1_000_000,
            "\(kind) moved \(after - before) bytes through the tunnel: not through it"
        )
    }

    @Test func `lumeEngine`() async throws {
        try await run(.lumeEngine)
    }

    @Test func `ksPlayer`() async throws {
        try await run(.ksPlayer)
    }
}

private extension String {
    func appendLine(to path: String) throws {
        if let handle = FileHandle(forWritingAtPath: path) {
            _ = try? handle.seekToEnd()
            try handle.write(contentsOf: Data(utf8))
            try handle.close()
        } else {
            try write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
