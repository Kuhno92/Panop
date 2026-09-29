import Darwin
import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import PanopEPG
import Testing

/// Performance measurements for the catalog import path.
///
/// Off unless `PANOP_BENCHMARK=1`, and only meaningful in an optimized build:
/// Debug is `-Onone`, which makes every number here fiction. Run it with
///
///     TEST_RUNNER_PANOP_BENCHMARK=1 xcodebuild test -project Panop.xcodeproj \
///       -scheme PanopTests -destination 'platform=macOS' -configuration Release \
///       ENABLE_TESTABILITY=YES -derivedDataPath /tmp/panop-dd-bench \
///       -clonedSourcePackagesDirPath ~/Library/Developer/Panop-SharedSPM
///
/// Fixtures are generated per run and never committed. Numbers are only
/// comparable on the same machine, so read them as ratios and as pass/fail
/// against "does this feel instant", not as absolutes.
@Suite(
    "Catalog benchmarks",
    .enabled(if: ProcessInfo.processInfo.environment["PANOP_BENCHMARK"] == "1"),
    .serialized
)
struct CatalogBenchmarks {
    private static let playlist = "bench"

    private func peakMemoryMB() -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss) / 1_048_576 // bytes on macOS
    }

    /// The hosted app's stdout is not captured by `xcodebuild`, so results go
    /// to a file as well.
    private func record(_ line: String) {
        print("BENCH \(line)")
        let url = URL(fileURLWithPath: "/tmp/panop-bench-results.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func timed<Result>(_ label: String, _ body: () async throws -> Result) async throws -> Result {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await body()
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        record("\(label): \(String(format: "%.2f", seconds)) s (peak \(peakMemoryMB()) MB)")
        return result
    }

    @Test
    func `import a 100k entry playlist`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let importer = CatalogImporter(
            store: catalog.store,
            transport: StubTransport { _ in (404, "") },
            batchSize: 1000
        )

        let full = try writeTemporaryFile(playlistText(live: 0 ..< 80000, movies: 0 ..< 20000))
        let store = catalog.store

        let cold = try await timed("cold import, 100k entries") {
            try await importer.importM3U(playlist: Self.playlist, source: .file(path: full))
        }
        #expect(cold.kinds.reduce(0) { $0 + $1.summary.inserted } == 100_000)

        let unchanged = try await timed("forced re-import, nothing changed") {
            try await importer.importM3U(playlist: Self.playlist, source: .file(path: full), force: true)
        }
        #expect(unchanged.kinds.reduce(0) { $0 + $1.summary.unchanged } == 100_000)

        let skipped = try await timed("re-import, unchanged file skipped by digest") {
            try await importer.importM3U(playlist: Self.playlist, source: .file(path: full))
        }
        #expect(skipped.outcome == .unchanged)

        // 2% of live channels changed group, 3% removed.
        let edited = try writeTemporaryFile(
            playlistText(live: 0 ..< 1600, group: "Sport") + playlistText(live: 1600 ..< 77600)
                .split(separator: "\n").dropFirst().joined(separator: "\n")
                + "\n" + playlistText(live: 0 ..< 0, movies: 0 ..< 20000).split(separator: "\n").dropFirst()
                .joined(separator: "\n")
        )
        let refreshed = try await timed("re-import, 2% changed and 3% removed") {
            try await importer.importM3U(playlist: Self.playlist, source: .file(path: edited))
        }
        let live = refreshed.kinds.first { $0.kind == .live }
        record("  updated \(live?.summary.updated ?? -1), removed \(live?.removed ?? -1)")

        _ = try await timed("page all 77k live ids, 2000 per page") {
            var count = 0
            var cursor: String?
            while true {
                let page = try await store.entryIDs(kind: .live, playlist: Self.playlist, after: cursor, limit: 2000)
                guard let last = page.last else { break }
                count += page.count
                cursor = last
            }
            return count
        }
        _ = try await timed("count live entries") {
            try await store.entryCount(kind: .live, playlist: Self.playlist)
        }
    }

    @Test
    func `import a large guide`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }

        // 400 channels x 500 half-hour programmes = 200k rows, about 60 MB.
        let day = Date(timeIntervalSince1970: 1_790_640_000)
        func guide(slots: Range<Int>, title: String = "Show") -> String {
            var parts = ["<tv>"]
            for channel in 0 ..< 400 {
                parts
                    .append(
                        #"<channel id="channel\#(channel).de"><display-name>Channel \#(channel)</display-name></channel>"#
                    )
            }
            for channel in 0 ..< 400 {
                for slot in slots {
                    let start = day.addingTimeInterval(TimeInterval(slot * 1800))
                    let stop = start.addingTimeInterval(1800)
                    parts.append(
                        #"<programme start="\#(stamp(start))" stop="\#(stamp(stop))" channel="channel\#(channel).de">"#
                            + "<title>\(title) \(slot)</title>"
                            + "<desc>A description of show \(slot) on channel \(channel).</desc></programme>"
                    )
                }
            }
            parts.append("</tv>")
            return parts.joined(separator: "\n")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        func stamp(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return String(
                format: "%04d%02d%02d%02d%02d00 +0000",
                parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
            )
        }

        let window = day ... day.addingTimeInterval(400 * 3600)
        let url = try #require(URL(string: "http://panel.example/xmltv.php"))
        func run(_ body: String, window: ClosedRange<Date>) async throws -> EPGImportReport {
            let importer = CatalogImporter(
                store: catalog.store,
                transport: StubTransport(chunkSize: 65536) { _ in (200, body) },
                batchSize: 1000
            )
            return try await importer.importEPG(playlist: Self.playlist, url: url, window: window)
        }

        let full = guide(slots: 0 ..< 500)
        record("  guide fixture: \(full.utf8.count / 1_000_000) MB")

        let cold = try await timed("cold guide import, 200k programmes") {
            try await run(full, window: window)
        }
        #expect(cold.programmes.inserted == 200_000)

        let unchanged = try await timed("guide refresh, nothing changed") {
            try await run(full, window: window)
        }
        #expect(unchanged.programmes.unchanged == 200_000)

        // Slots 0..<100 have ended; 100 new slots appear at the far end.
        let later = day.addingTimeInterval(100 * 1800) ... day.addingTimeInterval(500 * 3600)
        let rolled = try await timed("guide refresh, window moved on by 20%") {
            try await run(guide(slots: 100 ..< 600), window: later)
        }
        record(
            "  expired \(rolled.removedExpired), stale \(rolled.removedStale), inserted \(rolled.programmes.inserted)"
        )

        let rescheduled = try await timed("guide refresh, 100 titles per channel changed and 5 slots dropped") {
            try await run(guide(slots: 100 ..< 595, title: "Renamed"), window: later)
        }
        record("  updated \(rescheduled.programmes.updated), stale \(rescheduled.removedStale)")
    }
}
