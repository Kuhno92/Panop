import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

/// What the channel list costs against a real provider.
///
/// Off unless `PANOP_DEV_XTREAM=url|username|password` is set, and the login is read from the
/// environment only: it is never written to a file, a log or the repository. Numbers mean
/// something only in an optimised build, like the other benchmarks (see `CatalogBenchmarks`).
///
///     TEST_RUNNER_PANOP_DEV_XTREAM='http://host:9191|user|pass' xcodebuild test ... -configuration Release
@Suite(
    "Real provider benchmarks",
    .enabled(if: ProcessInfo.processInfo.environment["PANOP_DEV_XTREAM"] != nil),
    .serialized
)
@MainActor
struct RealProviderBenchmarks {
    private func record(_ line: String) {
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

    private func milliseconds(_ body: () throws -> Void) rethrows -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        try body()
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    private func credentials() throws -> ProviderCredentials {
        let parts = (ProcessInfo.processInfo.environment["PANOP_DEV_XTREAM"] ?? "").split(separator: "|")
            .map(String.init)
        try #require(parts.count == 3)
        return ProviderCredentials(baseURL: parts[0], username: parts[1], password: parts[2])
    }

    /// The list as it is now: pages read in the background and appended. Scrolled to the end while
    /// a ticker on the main thread notes the longest it was kept waiting.
    private func measurePaging(_ container: ModelContainer, clock: ContinuousClock) async {
        let model = CatalogListModel()
        var longestGap = 0.0
        var scrolling = true
        let ticker = Task { @MainActor in
            var last = ContinuousClock.now
            while scrolling {
                try? await Task.sleep(for: .milliseconds(2))
                let now = ContinuousClock.now
                let gap = now - last
                longestGap = max(
                    longestGap,
                    Double(gap.components.attoseconds) / 1e15 + Double(gap.components.seconds) * 1000
                )
                last = now
            }
        }
        model.show(ListSpec(kind: .live), in: container)
        let began = clock.now
        while model.rows.count < 1026, clock.now - began < .seconds(20) {
            if let last = model.rows.last {
                model.rowAppeared(last)
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        scrolling = false
        await ticker.value
        record(String(
            format: "REAL paged list: %d rows in pages of %d then %d; longest main-thread wait scrolling to the end %.1f ms",
            model.rows.count, CatalogListModel.firstPage, CatalogListModel.nextPage, longestGap
        ))
    }

    @Test
    func `the channel list against a real provider`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let importer = CatalogImporter(store: catalog.store, transport: URLSessionTransport())
        let descriptor = try PlaylistDescriptor(id: "real", source: .xtream(credentials()))

        let clock = ContinuousClock()
        let began = clock.now
        let outcome = try await importer.sync(descriptor)
        let importSeconds = Double((clock.now - began).components.seconds)
        record(
            "REAL import \(importSeconds) s, kinds \(outcome.catalog.kinds.map { "\($0.kind.rawValue):\($0.imported)" })"
        )

        let context = ModelContext(catalog.container)
        for kind in [MediaKind.live, .movie, .series] {
            let names = LiveChannelQuery.categoryNames(kind: kind, source: nil, in: context)
            record("REAL categories for \(kind.rawValue): \(names.count): \(names.prefix(4))")
        }
        for order in [LiveOrder.name, .provider] {
            let page = LiveChannelQuery.descriptor(
                source: nil,
                search: "",
                limit: LiveChannelQuery.pageSize,
                order: order
            )
            var rows: [CatalogEntryRecord] = []
            let elapsed = try milliseconds { rows = try context.fetch(page) }
            record(
                "REAL first page by \(order.rawValue): \(rows.count) rows in \(elapsed) ms; first: \(rows.prefix(3).map(\.name))"
            )
        }

        // What the list pays each time it grows: it reads its whole result again, so the cost of
        // reaching further down is the cost of every row above.
        for size in [100, 300, 600, 1200, 5000] {
            let descriptor = LiveChannelQuery.descriptor(source: nil, search: "", limit: size, order: .provider)
            var count = 0
            let elapsed = try milliseconds { count = try context.fetch(descriptor).count }
            record(String(format: "REAL fetch of %d rows (%d returned): %.1f ms", size, count, elapsed))
        }

        await measurePaging(catalog.container, clock: clock)

        // What each row does on appearing: one guide lookup, on the main thread.
        let rows = try context.fetch(LiveChannelQuery.descriptor(
            source: nil, search: "", limit: 60, order: .provider
        ))
        var lookups: [Double] = []
        var shown = 0
        for row in rows {
            let elapsed = milliseconds {
                if !GuideLookup.upcoming(playlist: row.playlist, epgKey: row.epgKey, limit: 1, in: context).isEmpty {
                    shown += 1
                }
            }
            lookups.append(elapsed)
        }
        let sorted = lookups.sorted()
        record(String(
            format: "REAL guide lookup per row over %d rows (%d with a programme): "
                + "mean %.2f ms, median %.2f, p95 %.2f, max %.2f, total %.1f ms",
            rows.count, shown, lookups.reduce(0, +) / Double(max(lookups.count, 1)),
            sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.95)], sorted.last ?? 0, lookups.reduce(0, +)
        ))
        record(
            "REAL programmes stored for guide check: \((try? context.fetchCount(FetchDescriptor<EPGProgrammeRecord>())) ?? -1)"
        )
    }
}
