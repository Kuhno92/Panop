import Foundation
import Network
@testable import Panop
import PanopCore
import Testing

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func bump() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}

/// A TCP server that only counts who connected, on every interface. Nothing is ever answered.
private final class CountingServer: @unchecked Sendable {
    private let listener: NWListener
    private let counter: Counter
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
        let counter = Counter()
        self.counter = counter
        listener.newConnectionHandler = { connection in
            counter.bump()
            connection.cancel()
        }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
        port = listener.port?.rawValue ?? 0
    }

    var connections: Int {
        counter.value
    }

    deinit {
        listener.cancel()
    }
}

/// An address of this machine that is not loopback: a system proxy setting may skip loopback, which would
/// make a leak test pass for the wrong reason.
private func lanAddress() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let entry = pointer.pointee
        guard let address = entry.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
              entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, entry.ifa_flags & UInt32(IFF_UP) != 0
        else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        let text = String(cString: host)
        if !text.hasPrefix("169.254.") {
            return text
        }
    }
    return nil
}

@Suite("Provider traffic never leaks", .serialized)
struct ProviderNetworkLeakTests {
    private func request(_ host: String, _ port: UInt16) -> HTTPRequest {
        HTTPRequest(url: URL(string: "http://\(host):\(port)/x")!, timeout: 4)
    }

    @Test func `with the tunnel down, nothing is sent and the server sees no connection`() async throws {
        let server = try CountingServer()
        let network = ProviderNetwork()
        network.setRoute(.tunnelDown)
        await #expect(throws: NetworkBlock.tunnelNotConnected) {
            try await network.transport.send(request("127.0.0.1", server.port))
        }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(server.connections == 0)
    }

    @Test func `with a required VPN missing, nothing is sent`() async throws {
        let server = try CountingServer()
        let network = ProviderNetwork()
        network.setSystemBlock(.vpnRequired)
        await #expect(throws: NetworkBlock.vpnRequired) {
            try await network.transport.send(request("127.0.0.1", server.port))
        }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(server.connections == 0)
    }

    @Test func `a dead tunnel proxy fails the request instead of going direct`() async throws {
        guard let lan = lanAddress() else { return }
        let server = try CountingServer()
        let network = ProviderNetwork()
        // A proxy nobody listens on: if anything went direct, the server would see it.
        network.setRoute(.tunnel(ProxyEndpoint(socksPort: 1, httpPort: 1, username: "u", password: "p")))
        await #expect(throws: (any Error).self) {
            try await network.transport.send(request(lan, server.port))
        }
        try? await Task.sleep(for: .milliseconds(500))
        #expect(server.connections == 0)
    }

    @Test func `a direct route does reach the server (the test would otherwise prove nothing)`() async throws {
        guard let lan = lanAddress() else { return }
        let server = try CountingServer()
        let network = ProviderNetwork()
        _ = try? await network.transport.send(request(lan, server.port))
        try? await Task.sleep(for: .milliseconds(500))
        #expect(server.connections >= 1)
    }
}
