import Foundation

/// Which channels of the person's playlist show a match: scores every programme that could be it, keeps the best
/// line of each channel, and puts the likeliest first.
public enum MatchChannelResolver {
    /// A cheap first look at a guide line, before its description is read: whether it names a team of one of these
    /// matches, or is sport at all. A guide has hundreds of thousands of lines and a day has a handful of matches, so
    /// everything else is left unread.
    public static func isCandidate(_ snippet: ProgrammeSnippet, for matches: [MatchSignature]) -> Bool {
        let headline = TeamNames.tokens(snippet.title + " | " + (snippet.subtitle ?? ""))
        if matches.contains(where: { $0.home.isNamed(in: headline) || $0.away.isNamed(in: headline) }) {
            return true
        }
        return MatchChannelScorer.isSportLike(headline: headline, categories: snippet.categories)
    }

    /// - Parameters:
    ///   - programmes: the guide lines at the time of the match, read by ``PreparedProgramme``. A line whose channel is
    ///     not in `channels` is ignored.
    ///   - remembered: the channels the person chose for this league before.
    /// - Returns: every channel that scores as "possible" or better, best first. When nothing reads as the match
    ///   itself, the sport programmes at the time (which name no team) are offered instead, as "possible".
    public static func resolve(
        _ match: MatchSignature,
        programmes: [PreparedProgramme],
        channels: [String: ChannelCandidate],
        remembered: Set<String> = []
    ) -> [MatchLink] {
        var best: [String: MatchLink] = [:]
        // Read once per channel, and only for a channel with a programme that names a team: most never are.
        var facts: [String: ChannelFacts] = [:]
        var showsLeague: [String: Bool] = [:]
        func bonus(_ channel: ChannelCandidate) -> Int {
            let known = facts[channel.id] ?? ChannelFacts(channel)
            facts[channel.id] = known
            let shows = showsLeague[channel.id] ?? known.showsLeague(of: match)
            showsLeague[channel.id] = shows
            return known.bonus(for: match, remembered: remembered.contains(channel.id), showsLeague: shows)
        }

        for programme in programmes {
            guard let base = MatchChannelScorer.base(match, programme: programme),
                  let channel = channels[programme.snippet.channelID]
            else { continue }
            let score = MatchChannelScorer.finish(base, bonus: bonus(channel))
            guard score.tier >= .possible else { continue }
            keep(MatchLink(channel: channel, programme: programme.snippet, score: score), in: &best)
        }

        if !best.values.contains(where: { $0.score.tier >= .likely }) {
            for programme in programmes {
                guard let channel = channels[programme.snippet.channelID], best[channel.id] == nil,
                      MatchChannelScorer.isGeneric(match, programme: programme)
                else { continue }
                let base = MatchChannelScorer.Base(value: 30, reason: .genericSport)
                let score = MatchChannelScorer.finish(base, bonus: min(15, bonus(channel)))
                keep(MatchLink(channel: channel, programme: programme.snippet, score: score), in: &best)
            }
        }
        return best.values.sorted { ordered($0, $1, remembered: remembered) }
    }

    private typealias ChannelFacts = MatchChannelScorer.ChannelFacts

    private static func keep(_ link: MatchLink, in best: inout [String: MatchLink]) {
        if let existing = best[link.id], existing.score.value >= link.score.value {
            return
        }
        best[link.id] = link
    }

    /// How sure it is (as a tier: a remembered channel never goes ahead of a surer one), then the channels the person
    /// chose before, then the score, then favourites, then quality, then name, so the order never changes by chance.
    /// The score tops out at 100, so a channel that names both teams cannot be told from another by the score alone.
    private static func ordered(_ lhs: MatchLink, _ rhs: MatchLink, remembered: Set<String>) -> Bool {
        if lhs.score.tier != rhs.score.tier {
            return lhs.score.tier > rhs.score.tier
        }
        let (lhsChosen, rhsChosen) = (remembered.contains(lhs.id), remembered.contains(rhs.id))
        if lhsChosen != rhsChosen {
            return lhsChosen
        }
        if lhs.score.value != rhs.score.value {
            return lhs.score.value > rhs.score.value
        }
        if lhs.channel.isFavourite != rhs.channel.isFavourite {
            return lhs.channel.isFavourite
        }
        if lhs.channel.qualityRank != rhs.channel.qualityRank {
            return lhs.channel.qualityRank > rhs.channel.qualityRank
        }
        return lhs.channel.name.localizedCompare(rhs.channel.name) == .orderedAscending
    }
}
