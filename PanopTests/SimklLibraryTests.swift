import Foundation
@testable import Panop
import PanopCore
import PanopSimkl
import Testing

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var activityCalls = 0
    private var libraryCalls = 0
    private var stamp: String

    init(stamp: String) {
        self.stamp = stamp
    }

    func changeStamp(_ new: String) {
        lock.withLock { stamp = new }
    }

    func activities() -> SimklActivities {
        lock.withLock {
            activityCalls += 1
            return SimklActivities(all: stamp)
        }
    }

    func library() -> [SimklListItem] {
        lock.withLock { libraryCalls += 1 }
        return [SimklListItem(kind: .movie, tmdbID: 603, status: .plantowatch)]
    }

    var counts: (activities: Int, library: Int) {
        lock.withLock { (activityCalls, libraryCalls) }
    }
}

@Suite("Simkl library", .serialized, .engineGate)
@MainActor
struct SimklLibraryTests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/library.json")
    }

    private func make(_ counter: Counter, at url: URL?) -> SimklLibrary {
        SimklLibrary(
            cacheURL: url,
            activities: { counter.activities() },
            library: { counter.library() }
        )
    }

    @Test
    func `the lists are fetched only when Simkl says something changed`() async {
        let counter = Counter(stamp: "A")
        let library = make(counter, at: nil)

        await library.refresh()
        await library.refresh()
        #expect(counter.counts.library == 1, "the second check saw the same stamp")

        counter.changeStamp("B")
        await library.refresh()
        #expect(counter.counts.library == 2)
        #expect(library.items.count == 1)
    }

    @Test
    func `a restart keeps the lists and does not fetch them again while nothing changed`() async {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let counter = Counter(stamp: "A")
        await make(counter, at: location).refresh()

        let restarted = make(counter, at: location)
        #expect(restarted.items.count == 1)
        await restarted.refresh()

        #expect(counter.counts.library == 1)
    }

    @Test
    func `clearing forgets the lists and the stamp`() async {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let counter = Counter(stamp: "A")
        let library = make(counter, at: location)
        await library.refresh()

        library.clear()
        #expect(library.items.isEmpty)
        await library.refresh()

        #expect(counter.counts.library == 2, "after clearing, the same stamp is new again")
    }
}
