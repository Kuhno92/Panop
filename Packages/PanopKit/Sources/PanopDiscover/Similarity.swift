import Foundation

/// How alike two titles are, from 0 to 1, by what a provider tells about them. A weighted sum of
/// overlaps, not a learned model: every part is something a person could check by looking at the
/// two titles side by side.
enum Similarity {
    static func score(_ candidate: DiscoveryTitle, to seed: DiscoveryTitle, rules: RailRules) -> Double {
        var score = 0.0
        if !candidate.genres.isEmpty, !seed.genres.isEmpty {
            score += rules.genreWeight * jaccard(candidate.genres, seed.genres)
        }
        if !candidate.cast.isEmpty, !seed.cast.isEmpty {
            score += rules.castWeight * jaccard(candidate.cast, seed.cast)
        }
        if let one = candidate.category, let other = seed.category, one == other {
            score += rules.categoryWeight
        }
        if let one = candidate.year, let other = seed.year {
            score += rules.yearWeight * Swift.max(0, 1 - Double(abs(one - other)) / rules.yearSpan)
        }
        if let one = candidate.rating, let other = seed.rating {
            score += rules.ratingWeight * Swift.max(0, 1 - abs(one - other) / 3)
        }
        if let stem = TitleText.stem(of: seed.name), stem == TitleText.stem(of: candidate.name) {
            score += rules.franchiseWeight
        }
        return Swift.min(score, 1)
    }

    private static func jaccard(_ one: Set<String>, _ other: Set<String>) -> Double {
        let union = one.union(other).count
        return union == 0 ? 0 : Double(one.intersection(other).count) / Double(union)
    }
}
