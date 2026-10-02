import Foundation
import PanopCore

/// Turns a library, a viewing history and a list of what is popular into rails of titles, all drawn
/// from the library and nothing else.
///
/// Pure: the same input gives the same rails, and the time arrives as part of the input. Rails are
/// built in priority order and a title goes in the first one that wants it, so none appears twice.
public enum RailBuilder {
    public static func build(_ input: DiscoveryInput, rules: RailRules = .standard) -> [Rail] {
        let pool = unique(input.titles.filter { isSuggestable($0, in: input, includingWatched: false) })
        let watchedPool = unique(input.titles.filter { isSuggestable($0, in: input, includingWatched: true) })
        let year = currentYear(input.now)
        let kinds: [MediaKind] = [.movie, .series]

        var rails: [Rail] = []
        var used = Set<String>()
        func add(_ kind: RailKind, _ candidates: [DiscoveryTitle], subject: String? = nil, minimum: Int? = nil) {
            let fresh = candidates.filter { !used.contains($0.key) }.prefix(rules.railSize)
            guard fresh.count >= (minimum ?? rules.minimumRailSize) else { return }
            used.formUnion(fresh.map(\.key))
            rails.append(Rail(kind: kind, keys: fresh.map(\.key), subject: subject))
        }

        add(.onYourList, onYourList(in: pool, input: input), minimum: rules.minimumPersonalRailSize)
        for kind in kinds {
            add(.trending(kind), trending(for: kind, in: pool, input: input))
        }
        for (seed, title) in seedTitles(input).prefix(rules.becauseRails) {
            add(.becauseYouWatched(seed: seed.key), similar(to: title, in: pool, rules: rules), subject: title.name)
        }
        for kind in kinds {
            add(.newReleases(kind), newReleases(of: kind, in: pool, year: year, rules: rules))
        }
        add(.mostWatched, mostWatched(in: watchedPool, input: input, rules: rules))
        for kind in kinds {
            add(.topRated(kind), topRated(of: kind, in: pool, rules: rules))
        }
        for kind in kinds {
            for (genre, titles) in genreGroups(of: kind, in: pool, rules: rules).prefix(rules.maxGenreRails) {
                add(.genre(kind, genre), titles, subject: genre)
            }
        }
        for (stem, titles) in franchises(in: pool, rules: rules).prefix(rules.maxFranchiseRails) {
            add(.franchise(stem), titles, subject: stem, minimum: rules.franchiseMinimumTitles)
        }
        add(.classics(.movie), classics(in: pool, rules: rules))
        for (decade, titles) in decades(in: pool, year: year, rules: rules).prefix(rules.maxDecadeRails) {
            add(.decade(.movie, decade), titles)
        }
        for kind in kinds {
            let day = Int(input.now.timeIntervalSince1970 / 86400)
            if let pick = pickOfTheDay(of: kind, in: pool, day: day, used: used, rules: rules) {
                add(.pickOfTheDay(kind), [pick], minimum: 1)
            }
        }
        return rails
    }

    // MARK: - What may be suggested

    private static func isSuggestable(
        _ title: DiscoveryTitle,
        in input: DiscoveryInput,
        includingWatched: Bool
    ) -> Bool {
        guard title.kind == .movie || title.kind == .series, !title.isAdult, title.hasPoster,
              !input.hidden.contains(title.key)
        else { return false }
        if let category = title.category, input.hiddenCategories[title.kind]?.contains(category) == true {
            return false
        }
        if let id = title.tmdbID, input.finishedElsewhere.contains(id) {
            return false
        }
        return includingWatched || !input.unavailable.contains(title.key)
    }

    /// One entry for a title the provider lists several times (different versions of the same
    /// film): the best rated, then the one with an id, then by key so the choice never varies.
    private static func unique(_ titles: [DiscoveryTitle]) -> [DiscoveryTitle] {
        var best: [String: DiscoveryTitle] = [:]
        for title in titles {
            let id = TitleText.sameTitleKey(name: title.name, year: title.year) + "|" + title.kind.rawValue
            guard let current = best[id] else {
                best[id] = title
                continue
            }
            let better = (title.rating ?? 0, title.tmdbID != nil ? 1 : 0, current.key)
                > (current.rating ?? 0, current.tmdbID != nil ? 1 : 0, title.key)
            if better {
                best[id] = title
            }
        }
        return best.values.sorted { $0.key < $1.key }
    }

    private static func currentYear(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.component(.year, from: date)
    }

    // MARK: - The rails

    /// The titles on the person's own list that the library has, in the order they keep them.
    private static func onYourList(in pool: [DiscoveryTitle], input: DiscoveryInput) -> [DiscoveryTitle] {
        var byID: [String: DiscoveryTitle] = [:]
        for title in pool {
            if let id = title.tmdbID {
                byID["\(title.kind.rawValue)|\(id)"] = title
            }
        }
        return input.planned.sorted { ($0.score, $1.tmdbID) > ($1.score, $0.tmdbID) }
            .compactMap { byID["\($0.kind.rawValue)|\($0.tmdbID)"] }
    }

    private static func trending(
        for kind: MediaKind,
        in pool: [DiscoveryTitle],
        input: DiscoveryInput
    ) -> [DiscoveryTitle] {
        var byID: [Int: DiscoveryTitle] = [:]
        for title in pool where title.kind == kind {
            if let id = title.tmdbID, byID[id] == nil {
                byID[id] = title
            }
        }
        return input.trending
            .filter { $0.kind == kind }
            .sorted { ($0.score, $1.tmdbID) > ($1.score, $0.tmdbID) }
            .compactMap { byID[$0.tmdbID] }
    }

    /// The strongest seeds that are known, each with what is known about it.
    private static func seedTitles(_ input: DiscoveryInput) -> [(DiscoverySeed, DiscoveryTitle)] {
        let known = Dictionary(input.titles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return input.seeds
            .sorted { ($0.weight, $1.key) > ($1.weight, $0.key) }
            .compactMap { seed in
                (input.seedTitles[seed.key] ?? known[seed.key]).map { (seed, $0) }
            }
            .filter { $0.1.kind == .movie || $0.1.kind == .series }
    }

    private static func similar(
        to seed: DiscoveryTitle,
        in pool: [DiscoveryTitle],
        rules: RailRules
    ) -> [DiscoveryTitle] {
        pool
            .filter { $0.kind == seed.kind && $0.key != seed.key }
            .map { ($0, Similarity.score($0, to: seed, rules: rules)) }
            .filter { $0.1 >= rules.similarityMinimum }
            .sorted { ($0.1, $0.0.rating ?? 0, $1.0.key) > ($1.1, $1.0.rating ?? 0, $0.0.key) }
            .map(\.0)
    }

    private static func newReleases(
        of kind: MediaKind,
        in pool: [DiscoveryTitle],
        year: Int,
        rules: RailRules
    ) -> [DiscoveryTitle] {
        pool
            .filter { title in
                guard title.kind == kind, let released = title.year,
                      let rating = trusted(title.rating, rules) else { return false }
                return released >= year - rules.newReleaseYears && released <= year && rating >= rules
                    .newReleaseMinimumRating
            }
            .sorted { ($0.year ?? 0, $0.rating ?? 0, $1.key) > ($1.year ?? 0, $1.rating ?? 0, $0.key) }
    }

    private static func mostWatched(
        in pool: [DiscoveryTitle],
        input: DiscoveryInput,
        rules: RailRules
    ) -> [DiscoveryTitle] {
        let known = Dictionary(pool.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return input.playCounts
            .filter { $0.times >= rules.mostWatchedMinimumPlays }
            .sorted { ($0.times, $1.key) > ($1.times, $0.key) }
            .compactMap { known[$0.key] }
    }

    private static func topRated(of kind: MediaKind, in pool: [DiscoveryTitle], rules: RailRules) -> [DiscoveryTitle] {
        pool
            .filter { title in
                guard title.kind == kind, let rating = trusted(title.rating, rules) else { return false }
                return rating >= rules.topRatedMinimum
            }
            .sorted { ($0.rating ?? 0, $0.year ?? 0, $1.key) > ($1.rating ?? 0, $1.year ?? 0, $0.key) }
    }

    /// Genres with enough well-liked titles for a rail, the biggest first, each with its titles best first.
    private static func genreGroups(of kind: MediaKind, in pool: [DiscoveryTitle], rules: RailRules) -> [(
        String,
        [DiscoveryTitle]
    )] {
        var groups: [String: [DiscoveryTitle]] = [:]
        for title in pool where title.kind == kind {
            guard let rating = trusted(title.rating, rules), rating >= rules.genreMinimumRating else { continue }
            for genre in title.genres {
                groups[genre, default: []].append(title)
            }
        }
        return groups
            .filter { $0.value.count >= rules.minimumRailSize }
            .map { genre, titles in
                (genre, titles.sorted { ($0.rating ?? 0, $1.key) > ($1.rating ?? 0, $0.key) })
            }
            .sorted { ($0.1.count, $1.0) > ($1.1.count, $0.0) }
    }

    /// Film series: titles that share a stem, three or more of them, in order of release.
    private static func franchises(in pool: [DiscoveryTitle], rules: RailRules) -> [(String, [DiscoveryTitle])] {
        var groups: [String: [DiscoveryTitle]] = [:]
        for title in pool where title.kind == .movie {
            if let stem = TitleText.stem(of: title.name) {
                groups[stem, default: []].append(title)
            }
        }
        return groups
            .filter { $0.value.count >= rules.franchiseMinimumTitles }
            .map { stem, titles in
                (stem, titles.sorted { ($0.year ?? .max, $0.name, $0.key) < ($1.year ?? .max, $1.name, $1.key) })
            }
            .sorted { ($0.1.count, $1.0) > ($1.1.count, $0.0) }
    }

    private static func classics(in pool: [DiscoveryTitle], rules: RailRules) -> [DiscoveryTitle] {
        pool
            .filter { title in
                guard title.kind == .movie, let released = title.year,
                      let rating = trusted(title.rating, rules) else { return false }
                return released < rules.classicsBeforeYear && rating >= rules.classicsMinimumRating
            }
            .sorted { ($0.rating ?? 0, $1.key) > ($1.rating ?? 0, $0.key) }
    }

    /// Decades before the current one, the best stocked first.
    private static func decades(in pool: [DiscoveryTitle], year: Int, rules: RailRules) -> [(Int, [DiscoveryTitle])] {
        var groups: [Int: [DiscoveryTitle]] = [:]
        for title in pool where title.kind == .movie {
            guard let released = title.year, let rating = trusted(title.rating, rules),
                  rating >= rules.decadeMinimumRating, released < (year / 10) * 10
            else { continue }
            groups[(released / 10) * 10, default: []].append(title)
        }
        return groups
            .filter { $0.value.count >= rules.minimumRailSize }
            .map { decade, titles in
                (decade, titles.sorted { ($0.rating ?? 0, $1.key) > ($1.rating ?? 0, $0.key) })
            }
            .sorted { ($0.1.count, $1.0) > ($1.1.count, $0.0) }
    }

    /// One well-liked title, the same all day and a different one tomorrow.
    private static func pickOfTheDay(
        of kind: MediaKind,
        in pool: [DiscoveryTitle],
        day: Int,
        used: Set<String>,
        rules: RailRules
    ) -> DiscoveryTitle? {
        let candidates = pool
            .filter { title in
                guard title.kind == kind, !used.contains(title.key),
                      let rating = trusted(title.rating, rules) else { return false }
                return rating >= rules.topRatedMinimum
            }
            .sorted { $0.key < $1.key }
        guard !candidates.isEmpty else { return nil }
        let offset = kind == .series ? 7919 : 0
        return candidates[(day + offset) % candidates.count]
    }

    /// A rating worth ranking by: present, above zero (providers send 0 for "none") and under the ceiling.
    private static func trusted(_ rating: Double?, _ rules: RailRules) -> Double? {
        guard let rating, rating > 0, rating <= rules.ratingCeiling else { return nil }
        return rating
    }
}
