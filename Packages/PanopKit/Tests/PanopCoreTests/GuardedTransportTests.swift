import Foundation
@testable import PanopCore
import Testing

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var hits: Int {
        lock.withLock { value }
    }

    func bump() {
        lock.withLock { value += 1 }
    }
}

private struct CountingTransport: HTTPTransport {
    let counter: Counter
    func send(_: HTTPRequest) async throws -> HTTPResponse {
        counter.bump()
        return HTTPResponse(statusCode: 200, body: Data())
    }

    func stream(_: HTTPRequest) async throws -> HTTPStreamResponse {
        counter.bump()
        return HTTPStreamResponse(statusCode: 200, chunks: HTTPChunks([]))
    }
}

struct GuardedTransportTests {
    private let request = HTTPRequest(url: URL(string: "https://example.invalid/x")!)

    @Test func `passes requests through while nothing blocks`() async throws {
        let counter = Counter()
        let transport = GuardedTransport(CountingTransport(counter: counter)) { nil }
        _ = try await transport.send(request)
        _ = try await transport.stream(request)
        #expect(counter.hits == 2)
    }

    @Test func `a block stops a send before the inner transport is touched`() async {
        let counter = Counter()
        let transport = GuardedTransport(CountingTransport(counter: counter)) { .tunnelNotConnected }
        await #expect(throws: NetworkBlock.tunnelNotConnected) { try await transport.send(request) }
        #expect(counter.hits == 0)
    }

    @Test func `a block stops a stream before the inner transport is touched`() async {
        let counter = Counter()
        let transport = GuardedTransport(CountingTransport(counter: counter)) { .vpnRequired }
        await #expect(throws: NetworkBlock.vpnRequired) { try await transport.stream(request) }
        #expect(counter.hits == 0)
    }

    @Test func `the gate is read on every request, so lifting a block takes effect at once`() async throws {
        let counter = Counter()
        let blocked = Counter()
        let transport = GuardedTransport(CountingTransport(counter: counter)) {
            blocked.hits == 0 ? .vpnRequired : nil
        }
        await #expect(throws: NetworkBlock.vpnRequired) { try await transport.send(request) }
        blocked.bump()
        _ = try await transport.send(request)
        #expect(counter.hits == 1)
    }

    @Test func `the description names no address`() {
        #expect(!NetworkBlock.vpnRequired.description.contains("http"))
    }
}
