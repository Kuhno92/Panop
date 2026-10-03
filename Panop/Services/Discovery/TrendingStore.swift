import Foundation
import PanopCore
import PanopDiscover
import PanopSimkl

nonisolated struct TrendingSnapshot: Codable, Equatable, Sendable {
    var fetchedAt: Date
    var entries: [TrendingEntry]
    /// The lists made from the same files ("Top Box Office", "Best of Netflix"). Nil in a snapshot saved
    /// before there were any, which is then read as out of date.
    var lists: [CuratedList]?
}

/// The trending lists, kept on disk and fetched at most once in a while. Public and the same for
/// everyone: nothing about the person goes out with the request.
actor TrendingStore {
    /// Simkl's lists move over days, so asking more often would only spend its bandwidth.
    static let maxAge: TimeInterval = 6 * 3600

    private let source: SimklTrendingSource
    private let cacheURL: URL?

    init(source: SimklTrendingSource, cacheURL: URL?) {
        self.source = source
        self.cacheURL = cacheURL
    }

    func cached() -> TrendingSnapshot? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(TrendingSnapshot.self, from: data)
    }

    /// New lists when the saved ones are older than `maxAge`, else nil. A failed fetch leaves the saved
    /// lists as they were and returns nil.
    func refreshIfStale(now: Date = .now) async -> TrendingSnapshot? {
        // A snapshot saved before there were lists has none, and is fetched again however young it is.
        if let saved = cached(), saved.lists != nil, now.timeIntervalSince(saved.fetchedAt) < Self.maxAge {
            return nil
        }
        guard let made = try? await source.snapshot(now: now) else { return nil }
        let snapshot = TrendingSnapshot(fetchedAt: now, entries: made.trending, lists: made.lists)
        save(snapshot)
        return snapshot
    }

    private func save(_ snapshot: TrendingSnapshot) {
        guard let cacheURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }

    nonisolated static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Discovery", isDirectory: true)
            .appendingPathComponent("trending.json")
    }
}
