import Foundation
import PanopCore
import PanopDiscover
import SwiftData

/// What the rails are built from besides the catalog: plain values, so it can cross to the store's
/// thread, and `Equatable`, so an unchanged one is recognised and nothing is rebuilt.
nonisolated struct DiscoveryContext: Equatable, Sendable {
    var seeds: [DiscoverySeed]
    var playCounts: [PlayCount]
    /// Watched, started or being watched: never suggested.
    var unavailable: Set<String>
    var hidden: Set<String>
    var hiddenCategories: [MediaKind: Set<String>]
    var trending: [TrendingEntry]
    /// On the person's own Simkl list to watch, and what they have finished there.
    var planned: [TrendingEntry] = []
    var watching: [TrendingEntry] = []
    var finishedElsewhere: Set<Int> = []
    /// Days since 1970. The date, not the moment: rails change at most daily, so a context made a
    /// minute later is the same one.
    var day: Int

    var now: Date {
        Date(timeIntervalSince1970: Double(day) * 86400 + 43200)
    }
}

/// The rails and what is needed to draw them, kept together so a cached copy is complete.
nonisolated struct DiscoveryResult: Codable, Equatable, Sendable {
    var rails: [Rail]
    var rows: [String: CatalogRow]
}

/// Builds the rails off the main thread, from the catalog and nothing else, and keeps the last result
/// on disk so Home can draw it before anything has been read.
///
/// Every read is bounded and uses an index: a few hundred titles of each kind, never the whole of a
/// library of ten thousand. The engine itself (`RailBuilder`) is pure and lives in the portable core.
actor DiscoveryStore {
    private let container: ModelContainer
    private let cacheURL: URL?

    /// Per read, so a candidate set stays a few hundred titles however large the library.
    static let candidateLimit = 500
    static let seriesLimit = 3000

    init(container: ModelContainer, cacheURL: URL?) {
        self.container = container
        self.cacheURL = cacheURL
    }

    /// The last result written, if there is one.
    func cached() -> DiscoveryResult? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(DiscoveryResult.self, from: data)
    }

    func build(_ discovery: DiscoveryContext) -> DiscoveryResult {
        let context = ModelContext(container)
        var records: [String: CatalogEntryRecord] = [:]
        func add(_ list: [CatalogEntryRecord]) {
            for record in list {
                records[Self.key(record)] = record
            }
        }
        let year = Calendar(identifier: .gregorian).component(.year, from: discovery.now)

        add(fetch(context, kind: .series, limit: Self.seriesLimit, sort: SortDescriptor(\.rating, order: .reverse)))
        add(fetch(context, kind: .movie, limit: Self.candidateLimit, sort: SortDescriptor(\.rating, order: .reverse)))
        add(fetch(
            context,
            kind: .movie,
            limit: Self.candidateLimit,
            sort: SortDescriptor(\.year, order: .reverse),
            minimumYear: year - 1
        ))
        add(trendingRecords(context, discovery.trending + discovery.planned + discovery.watching))
        // What the history points at, wherever it falls, and the neighbourhood of the strongest seeds.
        let known = seedAndPlayRecords(context, discovery)
        add(known)
        for record in known.prefix(4) where record.kindRaw == MediaKind.movie.rawValue {
            if let group = record.groupName {
                add(fetch(
                    context,
                    kind: .movie,
                    limit: Self.candidateLimit,
                    group: group,
                    sort: SortDescriptor(\.rating, order: .reverse)
                ))
            }
        }

        let titles = records.values.map(Self.title)
        let seedTitles = Dictionary(
            discovery.seeds.compactMap { seed in records[seed.key].map { (seed.key, Self.title($0)) } },
            uniquingKeysWith: { first, _ in first }
        )
        let rails = RailBuilder.build(DiscoveryInput(
            titles: titles,
            seeds: discovery.seeds,
            seedTitles: seedTitles,
            unavailable: discovery.unavailable,
            hidden: discovery.hidden,
            hiddenCategories: discovery.hiddenCategories,
            trending: discovery.trending,
            planned: discovery.planned,
            watching: discovery.watching,
            finishedElsewhere: discovery.finishedElsewhere,
            playCounts: discovery.playCounts,
            now: discovery.now
        ))
        let shown = Set(rails.flatMap(\.keys))
        let rows = Dictionary(
            records.filter { shown.contains($0.key) }.map { ($0.key, CatalogRow($0.value)) },
            uniquingKeysWith: { first, _ in first }
        )
        let result = DiscoveryResult(rails: rails, rows: rows)
        write(result)
        return result
    }

    // MARK: - Reads

    private func fetch(
        _ context: ModelContext,
        kind: MediaKind,
        limit: Int,
        group: String? = nil,
        sort: SortDescriptor<CatalogEntryRecord>,
        minimumYear: Int? = nil
    ) -> [CatalogEntryRecord] {
        var descriptor = FetchDescriptor<CatalogEntryRecord>(
            predicate: Self.predicate(kind: kind, group: group, minimumYear: minimumYear),
            sortBy: [sort]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Not adult, not an episode grouped under a show, of one kind, and optionally of one category or
    /// from a year on. Split by case: each is one simple predicate, which SwiftData can evaluate and the
    /// compiler can check.
    private static func predicate(kind: MediaKind, group: String?, minimumYear: Int?) -> Predicate<CatalogEntryRecord> {
        let raw = kind.rawValue
        if let group {
            return #Predicate { $0.kindRaw == raw && $0.isAdult == false && $0.groupName == group && $0.seriesID == nil
            }
        }
        if let minimumYear {
            return #Predicate {
                $0.kindRaw == raw && $0.isAdult == false && $0.seriesID == nil && $0.year >= minimumYear
            }
        }
        return #Predicate { $0.kindRaw == raw && $0.isAdult == false && $0.seriesID == nil }
    }

    /// The library's titles on a trending list, by TMDB id, through the index on it.
    private func trendingRecords(_ context: ModelContext, _ entries: [TrendingEntry]) -> [CatalogEntryRecord] {
        var found: [CatalogEntryRecord] = []
        for kind in [MediaKind.movie, .series] {
            let raw = kind.rawValue
            let wanted = Array(Set(entries.filter { $0.kind == kind }.map(\.tmdbID)))
            for start in stride(from: 0, to: wanted.count, by: 400) {
                let chunk = Array(wanted[start ..< Swift.min(start + 400, wanted.count)])
                let descriptor = FetchDescriptor<CatalogEntryRecord>(
                    predicate: #Predicate { $0.kindRaw == raw && $0.isAdult == false && chunk.contains($0.tmdbID) }
                )
                found += (try? context.fetch(descriptor)) ?? []
            }
        }
        return found
    }

    /// The titles named by the history: its seeds and what has been opened most, by key.
    private func seedAndPlayRecords(_ context: ModelContext, _ discovery: DiscoveryContext) -> [CatalogEntryRecord] {
        let keys = discovery.seeds.map(\.key) + discovery.playCounts.map(\.key)
        let ids = Array(Set(keys.map(UserStateStore.entryID(in:))))
        guard !ids.isEmpty else { return [] }
        let wanted = Set(keys)
        let descriptor = FetchDescriptor<CatalogEntryRecord>(predicate: #Predicate { ids.contains($0.id) })
        let all = (try? context.fetch(descriptor)) ?? []
        // An entry id can repeat across playlists, so the playlist is checked as well.
        return all.filter { wanted.contains(Self.key($0)) }
    }

    // MARK: - Conversion and cache

    private static func key(_ record: CatalogEntryRecord) -> String {
        UserStateStore.key(playlist: record.playlist, entry: record.id)
    }

    private static func title(_ record: CatalogEntryRecord) -> DiscoveryTitle {
        DiscoveryTitle(
            key: key(record),
            kind: record.kind,
            name: record.name,
            category: record.groupName,
            year: record.year == 0 ? nil : record.year,
            rating: record.rating,
            genres: TitleText.genres(from: record.genre),
            cast: TitleText.people(from: record.cast),
            tmdbID: record.tmdbID == 0 ? nil : record.tmdbID,
            isAdult: record.isAdult,
            hasPoster: (record.iconURL ?? "").hasPrefix("http")
        )
    }

    private func write(_ result: DiscoveryResult) {
        guard let cacheURL, let data = try? JSONEncoder().encode(result) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }
}
