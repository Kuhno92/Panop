import Foundation
import PanopCore
import PanopDiscover
import PanopSimkl

nonisolated struct TrendingSnapshot: Codable, Equatable, Sendable {
    var fetchedAt: Date
    var entries: [TrendingEntry]
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
        if let saved = cached(), now.timeIntervalSince(saved.fetchedAt) < Self.maxAge {
            return nil
        }
        guard let movies = try? await source.trending(.movie),
              let series = try? await source.trending(.series) else { return nil }
        let snapshot = TrendingSnapshot(fetchedAt: now, entries: movies + series)
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

extension SimklTrendingSource {
    /// The source as the app uses it, naming itself as Simkl's rules ask.
    static var panop: SimklTrendingSource {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return SimklTrendingSource(transport: URLSessionTransport(), userAgent: "Panop/\(version)")
    }
}
