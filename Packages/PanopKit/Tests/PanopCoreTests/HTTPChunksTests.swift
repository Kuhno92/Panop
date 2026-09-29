import Foundation
@testable import PanopCore
import Testing

@Suite("HTTP chunks")
struct HTTPChunksTests {
    @Test
    func `yields a fixed list in order`() async throws {
        let chunks = HTTPChunks([Data("a".utf8), Data("bc".utf8)])
        var seen: [String] = []
        for try await chunk in chunks {
            seen.append(String(bytes: chunk, encoding: .utf8) ?? "")
        }
        #expect(seen == ["a", "bc"])
    }

    /// The property the whole design leans on: nothing is produced until the
    /// consumer asks, so a slow consumer slows the producer.
    @Test
    func `produces a chunk only when asked for one`() async throws {
        let pulls = PullCounter()
        let chunks = HTTPChunks {
            {
                pulls.increment()
                return Data([0])
            }
        }

        var iterator = chunks.makeAsyncIterator()
        #expect(pulls.total == 0)
        _ = try await iterator.next()
        #expect(pulls.total == 1)
        _ = try await iterator.next()
        #expect(pulls.total == 2)
    }

    @Test
    func `each iteration starts fresh`() async throws {
        let chunks = HTTPChunks([Data([1]), Data([2])])
        var first = 0
        for try await _ in chunks {
            first += 1
        }
        var second = 0
        for try await _ in chunks {
            second += 1
        }
        #expect(first == 2)
        #expect(second == 2)
    }
}

private final class PullCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var total: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
