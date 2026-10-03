import Foundation
import SwiftData

/// One title's plays, as the recommendations read them.
nonisolated struct PlaySignal: Equatable, Sendable {
    var lastPlayedAt: Date
    var times: Int
    /// The series an episode belongs to, or empty.
    var parentKey: String
}

/// A title the person has shown a taste for, and how strongly. A series stands for all its episodes.
nonisolated struct TasteSeed: Equatable, Sendable {
    var key: String
    var weight: Double
}

/// What the person's own viewing says about what they like. Read only from the history already
/// on the device, and never sent anywhere.
extension UserStateStore {
    /// Each title is worth less the further back it was watched.
    static let seedDecay = 0.85
    /// Something stopped half way counts for this much of something finished.
    static let partialWeight = 0.6
    /// How far through counts as having watched enough of it to say something about taste.
    static let enoughWatched = 0.5

    /// The titles to recommend from, strongest first: what was finished, or watched more than
    /// halfway, the most recent counting most. Episodes count toward their series, so a show watched
    /// over many evenings is one seed and not many.
    ///
    /// Live channels never qualify: they have no end to reach, so they are not in `watched` or in
    /// `progress`.
    func tasteSeeds(limit: Int) -> [TasteSeed] {
        let eligible = plays.filter { key, _ in
            watched.contains(key) || (progress[key]?.fraction ?? 0) >= Self.enoughWatched
        }
        .sorted { ($0.value.lastPlayedAt, $0.key) > ($1.value.lastPlayedAt, $1.key) }

        var weights: [String: Double] = [:]
        for (rank, entry) in eligible.enumerated() {
            let seed = entry.value.parentKey.isEmpty ? entry.key : entry.value.parentKey
            let strength = watched.contains(entry.key) ? 1.0 : Self.partialWeight
            weights[seed, default: 0] += strength * pow(Self.seedDecay, Double(rank))
        }
        return weights
            .map { TasteSeed(key: $0.key, weight: $0.value) }
            .sorted { ($0.weight, $1.key) > ($1.weight, $0.key) }
            .prefix(Swift.max(limit, 0))
            .map(\.self)
    }

    /// How often each title has been opened, a series counting all its episodes, most first. For the
    /// rail of what is watched most, which then keeps only what is a film or a series.
    func playCounts(limit: Int) -> [(key: String, count: Int)] {
        var counts: [String: Int] = [:]
        for (key, play) in plays where play.times > 0 {
            counts[play.parentKey.isEmpty ? key : play.parentKey, default: 0] += play.times
        }
        return counts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(Swift.max(limit, 0))
            .map { (key: $0.key, count: $0.value) }
    }

    /// Forgets what was watched: the recently watched list, the watched marks and the play counts,
    /// and so what recommendations are drawn from. Favourites, hidden titles and resume points stay.
    func forgetViewingHistory() {
        for row in profileRows() where row.lastPlayedAt > .distantPast || row.isWatched || row.playCount > 0 {
            row.lastPlayedAt = .distantPast
            row.playCount = 0
            row.parentKey = ""
            row.isWatched = false
            if !row.isFavorite, !row.isHidden, row.positionSeconds == 0, row.rememberedEngine.isEmpty {
                context.delete(row)
            }
        }
        commit()
    }
}
