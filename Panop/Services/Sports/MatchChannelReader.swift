import Foundation
import PanopCatalog
import PanopCore
import PanopSports
import SwiftData

/// Finds, for each match of the day, the channels of the person's playlists that are showing it, by reading the guide.
///
/// It runs off the main thread on a context of its own. A guide has hundreds of thousands of lines and a day has a
/// handful
/// of matches, so it narrows before it reads: only the lines that end in the window of a match are fetched (the
/// `[playlist, stop]` index serves that), and of those only the ones that name a team or are sport are read in full.
actor MatchChannelReader {
    struct Request: Sendable {
        var fixtures: [Fixture]
        /// The playlists to look in.
        var playlists: [String]
        /// The channels the person chose before, by league: `CatalogRow.id`s.
        var remembered: [Int: Set<String>] = [:]
        /// The person's favourite channels, `CatalogRow.id`s.
        var favourites: Set<String> = []
    }

    struct Output: Sendable {
        var links: [Int: [MatchLink]] = [:]
        /// The channels behind the links, by `ChannelCandidate.id`.
        var rows: [String: CatalogRow] = [:]
    }

    /// A line of the guide, and where it came from.
    private struct GuideLine {
        var snippet: ProgrammeSnippet
        var playlist: String
        var key: String
    }

    private struct Target {
        var fixture: Int
        var league: Int?
        var signature: MatchSignature
    }

    private let container: ModelContainer
    /// More than a window can hold, so a runaway guide cannot take the screen with it.
    private let limit = 120_000

    init(container: ModelContainer) {
        self.container = container
    }

    func read(_ request: Request) -> Output {
        let signatures = request.fixtures.compactMap { fixture in MatchSignature(fixture).map { (
            fixture.id,
            fixture.leagueID,
            $0
        ) } }
        guard !signatures.isEmpty, !request.playlists.isEmpty else { return Output() }
        let matches = signatures.map(\.2)
        let low = matches.map { $0.kickoff.addingTimeInterval(-20 * 60) }.min() ?? .now
        let high = matches.map { $0.kickoff.addingTimeInterval(150 * 60) }.max() ?? .now

        let context = ModelContext(container)
        var candidates: [GuideLine] = []
        for playlist in request.playlists {
            candidates += lines(in: context, playlist: playlist, from: low, to: high, matches: matches)
        }
        guard !candidates.isEmpty else { return Output() }

        let channels = bestChannels(in: context, candidates: candidates)
        var prepared: [PreparedProgramme] = []
        var byID: [String: ChannelCandidate] = [:]
        var rows: [String: CatalogRow] = [:]
        for entry in candidates {
            guard let channel = channels["\(entry.playlist)|\(entry.key)"] else { continue }
            let candidate = ChannelCandidate(
                id: channel.id, name: channel.name, group: channel.groupName,
                qualityRank: Self.quality(of: channel.name), isFavourite: request.favourites.contains(channel.id)
            )
            byID[candidate.id] = candidate
            rows[candidate.id] = channel
            var snippet = entry.snippet
            snippet.channelID = candidate.id
            prepared.append(PreparedProgramme(snippet))
        }

        var output = Output()
        for (id, league, signature) in signatures {
            let remembered = league.flatMap { request.remembered[$0] } ?? []
            let links = MatchChannelResolver.resolve(
                signature,
                programmes: prepared,
                channels: byID,
                remembered: remembered
            )
            guard !links.isEmpty else { continue }
            output.links[id] = Array(links.prefix(6))
        }
        let used = Set(output.links.values.flatMap { $0.map(\.channel.id) })
        output.rows = rows.filter { used.contains($0.key) }
        return output
    }

    // MARK: - Reading

    /// The lines of one playlist's guide that end in the window and could be about one of the matches.
    private func lines(
        in context: ModelContext, playlist: String, from low: Date, to high: Date, matches: [MatchSignature]
    ) -> [GuideLine] {
        // A programme that ends after the window opens and starts before it closes. `stop` is what the index serves.
        let latestStop = high.addingTimeInterval(5 * 3600)
        var descriptor = FetchDescriptor<EPGProgrammeRecord>(predicate: #Predicate {
            $0.playlist == playlist && $0.stop >= low && $0.stop <= latestStop && $0.start <= high
        })
        descriptor.fetchLimit = limit
        let records = (try? context.fetch(descriptor)) ?? []
        var found: [GuideLine] = []
        for record in records {
            let categories = record.categoriesRaw.isEmpty ? [] : record.categoriesRaw.components(separatedBy: "\u{1F}")
            let snippet = ProgrammeSnippet(
                channelID: record.channelKey, start: record.start, stop: record.stop, title: record.title,
                subtitle: record.subtitle, details: record.details, categories: categories
            )
            if MatchChannelResolver.isCandidate(snippet, for: matches) {
                found.append(GuideLine(snippet: snippet, playlist: playlist, key: record.channelKey))
            }
        }
        return found
    }

    /// For each (playlist, guide key) of the lines, the best channel that has it: several channels share a guide as
    /// versions (UHD, HD, SD), and the best is the one to offer.
    private func bestChannels(
        in context: ModelContext, candidates: [GuideLine]
    ) -> [String: CatalogRow] {
        var keysByPlaylist: [String: Set<String>] = [:]
        for entry in candidates {
            keysByPlaylist[entry.playlist, default: []].insert(entry.key)
        }
        let live = MediaKind.live.rawValue
        var best: [String: CatalogRow] = [:]
        for (playlist, keys) in keysByPlaylist {
            // Optional, like the attribute: SQL compares them as they are.
            let wanted: [String?] = keys.map { Optional($0) }
            let descriptor = FetchDescriptor<CatalogEntryRecord>(predicate: #Predicate {
                $0.playlist == playlist && $0.kindRaw == live && wanted.contains($0.epgKey)
            })
            for record in (try? context.fetch(descriptor)) ?? [] {
                let row = CatalogRow(record)
                let key = "\(playlist)|\(EPGKey.normalize(record.epgKey ?? ""))"
                if let current = best[key], Self.quality(of: current.name) >= Self.quality(of: row.name) {
                    continue
                }
                best[key] = row
            }
        }
        return best
    }

    /// UHD above FHD above HD above SD, from what the name says; a name that says nothing counts as HD.
    nonisolated static func quality(of name: String) -> Int {
        let words = Set(TeamNames.tokens(name))
        if !words.isDisjoint(with: ["4k", "uhd", "2160p"]) {
            return 3
        }
        if !words.isDisjoint(with: ["fhd", "1080p", "1080"]) {
            return 2
        }
        if !words.isDisjoint(with: ["sd", "low", "480p", "576p"]) {
            return 0
        }
        return 1
    }
}
