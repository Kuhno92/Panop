import Foundation
import Observation
import PanopSimkl

private struct LibrarySnapshot: Codable {
    var activities: String
    var items: [SimklListItem]
}

/// The person's Simkl lists, kept on disk and fetched only when Simkl says they changed.
///
/// Asked for when the app opens and when an account is connected, never on a timer: one cheap check of
/// what changed, and the lists only when it differs from the check before.
@MainActor
@Observable
final class SimklLibrary {
    private(set) var items: [SimklListItem]

    private let activities: @Sendable () async throws -> SimklActivities
    private let library: @Sendable () async throws -> [SimklListItem]
    private let cacheURL: URL?
    @ObservationIgnored private var seen: String?

    init(
        cacheURL: URL? = SimklLibrary.defaultCacheURL,
        activities: @escaping @Sendable () async throws -> SimklActivities,
        library: @escaping @Sendable () async throws -> [SimklListItem]
    ) {
        self.cacheURL = cacheURL
        self.activities = activities
        self.library = library
        let saved = Self.load(cacheURL)
        items = saved?.items ?? []
        seen = saved?.activities
    }

    func refresh() async {
        guard let latest = try? await activities().all else { return }
        guard latest != seen || seen == nil else { return }
        guard let fresh = try? await library() else { return }
        items = fresh
        seen = latest
        save(LibrarySnapshot(activities: latest, items: fresh))
    }

    /// Forgets the lists, for when the account is disconnected: they were that account's.
    func clear() {
        items = []
        seen = nil
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    private func save(_ snapshot: LibrarySnapshot) {
        guard let cacheURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func load(_ url: URL?) -> LibrarySnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LibrarySnapshot.self, from: data)
    }

    nonisolated static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Simkl", isDirectory: true)
            .appendingPathComponent("library.json")
    }
}
