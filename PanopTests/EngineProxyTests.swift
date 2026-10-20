import Foundation
import Network
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

/// A stand-in for the tunnel's HTTP proxy: records what each connection says first, then refuses it.
private final class Heads: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []

    func add(_ text: String) {
        lock.withLock { all.append(text) }
    }

    var value: [String] {
        lock.withLock { all }
    }
}

private final class ProxyProbe: @unchecked Sendable {
    private let listener: NWListener
    private let heads = Heads()
    let port: UInt16

    init() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = {
            if case .ready = $0 {
                ready.signal()
            }
        }
        let heads = heads
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                if let data, let text = String(data: data, encoding: .utf8) {
                    heads.add(text)
                }
                let refusal = Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: refusal, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
        port = listener.port?.rawValue ?? 0
    }

    var requests: [String] {
        heads.value
    }

    deinit {
        listener.cancel()
    }
}

@Suite("Engines send their connections to the VPN proxy", .serialized, .engineGate)
@MainActor
struct EngineProxyTests {
    /// Loads a stream whose origin is a real, reachable address with a listener, through a proxy that refuses.
    /// The proxy must hear of the origin, with the login; the origin must hear nothing.
    private func check(_ kind: PlaybackEngineKind) async throws {
        let lan = try #require(lanAddress(), "no network address to test with")
        let origin = try CountingServer()
        let proxy = try ProxyProbe()
        let endpoint = ProxyEndpoint(
            socksPort: 1,
            httpPort: Int(proxy.port),
            username: "panopuser",
            password: "panoppass"
        )
        let engine = try #require(EngineRegistry.make(kind))
        let item = PlaybackItem(url: "http://\(lan):\(origin.port)/live/1.ts", mediaKind: .live, proxy: endpoint)

        let loading = Task {
            try? await engine.load(item)
            engine.play()
        }
        for _ in 0 ..< 160 where proxy.requests.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
        loading.cancel()
        await engine.stop()
        try? await Task.sleep(for: .milliseconds(300))

        let heard = proxy.requests.joined(separator: "\n")
        #expect(
            heard.contains("\(lan):\(origin.port)"),
            "\(kind) never asked the proxy for the origin. Heard: \(heard)"
        )
        #expect(origin.connections == 0, "\(kind) connected to the origin directly")
    }

    @Test func `lumeEngine`() async throws {
        try await check(.lumeEngine)
    }

    @Test func `ksPlayer`() async throws {
        try await check(.ksPlayer)
    }

    @Test func `the engines that cannot use the proxy are the ones that are skipped`() {
        #expect(Set(PlaybackEngineKind.allCases.filter { !$0.supportsProxy }) == [.avPlayer, .aetherEngine, .vlcKit])
    }
}
