import Foundation
@testable import Panop
import PanopSimkl
import Testing

private final class Sent: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[SimklWatched]] = []
    private var failures: [SimklError]

    init(failing: [SimklError] = []) {
        failures = failing
    }

    var all: [[SimklWatched]] {
        lock.withLock { batches }
    }

    func take(_ batch: [SimklWatched]) throws {
        try lock.withLock {
            if !failures.isEmpty {
                throw failures.removeFirst()
            }
            batches.append(batch)
        }
    }
}

@Suite("Simkl sync queue", .serialized, .engineGate)
@MainActor
struct SimklSyncTests {
    private func queueURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/queue.json")
    }

    private func sync(_ sent: Sent, url: URL?) -> SimklSync {
        SimklSync(queueURL: url, send: { try sent.take($0) }, sleep: { _ in await Task.yield() })
    }

    private func settle(_ until: () -> Bool) async {
        for _ in 0 ..< 200 where !until() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func `what is finished goes in one batch and the queue empties`() async {
        let sent = Sent()
        let sync = sync(sent, url: nil)
        sync.register("p|m", as: .movie(tmdb: 603))
        sync.register("p|e1", as: .episode(showTMDB: 1399, season: 1, number: 1))

        sync.finished("p|m")
        sync.finished("p|e1")
        await settle { sync.queued.isEmpty }

        #expect(sent.all.count == 1)
        #expect(sent.all.first?.count == 2)
    }

    @Test
    func `a title with no Simkl id, or finished while the switch is off, is not queued`() {
        let sync = sync(Sent(), url: nil)
        sync.register("p|x", as: nil)
        sync.register("p|m", as: .movie(tmdb: 1))

        sync.finished("p|x")
        sync.finished("p|unknown")
        sync.isEnabled = false
        sync.finished("p|m")

        #expect(sync.queued.isEmpty)
    }

    @Test
    func `finishing the same title twice queues it once`() {
        let sync = sync(Sent(failing: [.status(503)]), url: nil)
        sync.register("p|m", as: .movie(tmdb: 1))

        sync.finished("p|m")
        sync.finished("p|m")

        #expect(sync.queued.count == 1)
    }

    @Test
    func `a failed send keeps the queue and the next try sends it`() async {
        let sent = Sent(failing: [.status(503)])
        let sync = sync(sent, url: nil)
        sync.register("p|m", as: .movie(tmdb: 1))

        sync.finished("p|m")
        await settle { !sent.all.isEmpty }

        #expect(sent.all.count == 1, "the retry went through after the first failure")
        #expect(sync.queued.isEmpty)
    }

    @Test
    func `when signed out the queue waits and is sent after sign-in`() async {
        let sent = Sent(failing: [.unauthorized])
        let sync = sync(sent, url: nil)
        sync.register("p|m", as: .movie(tmdb: 1))
        sync.finished("p|m")
        await settle { false || sync.queued.isEmpty }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(sync.queued.count == 1)
        #expect(sent.all.isEmpty)

        sync.flushIfNeeded()
        await settle { sync.queued.isEmpty }

        #expect(sent.all.count == 1)
    }

    @Test
    func `the queue survives a restart`() async {
        let url = queueURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = sync(Sent(failing: [.unauthorized]), url: url)
        first.register("p|m", as: .movie(tmdb: 7))
        first.finished("p|m")
        try? await Task.sleep(for: .milliseconds(100))

        let second = sync(Sent(), url: url)

        #expect(second.queued.count == 1)
    }

    @Test
    func `discarding forgets what was waiting`() {
        let sync = sync(Sent(failing: [.unauthorized]), url: nil)
        sync.register("p|m", as: .movie(tmdb: 1))
        sync.finished("p|m")

        sync.discardQueue()

        #expect(sync.queued.isEmpty)
    }
}
