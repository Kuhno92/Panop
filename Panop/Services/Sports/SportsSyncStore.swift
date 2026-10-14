import Foundation
import Observation
import SwiftData

/// A league the person follows.
nonisolated struct SportsLeagueChoice: Equatable, Hashable, Identifiable, Sendable {
    var id: Int
    var name: String
    var country: String
}

/// A team the person follows.
nonisolated struct SportsTeamChoice: Equatable, Hashable, Identifiable, Sendable {
    var id: Int
    var name: String
    var short: String
    var logo: String?
    var leagueID: Int?
}

/// What the person chose in the sports hub, and the key, kept in the cloud container so it follows them to their other
/// devices (ADR 0009). It is read through explicit fetches, never `@Query` (ADR 0003).
///
/// Two devices can each write the same choice before either has seen the other's, and nothing can be unique in a
/// mirrored container, so a read keeps the newest row of each (profile, kind, key) and removes the others.
@MainActor
@Observable
final class SportsSyncStore {
    /// Counts up whenever something changed here or arrived from another device, for screens to read again.
    private(set) var revision = 0

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    private enum Kind {
        static let league = "league"
        static let team = "team"
        static let setupDone = "setupDone"
        static let showsTab = "showsTab"
        static let channel = "channel"
    }

    private static let separator = "\u{1F}"

    // MARK: - Leagues and teams

    func leagues(profile: String) -> [SportsLeagueChoice] {
        rows(profile: profile, kind: Kind.league).compactMap { row in
            guard let id = Int(row.key) else { return nil }
            let parts = row.value.components(separatedBy: Self.separator)
            return SportsLeagueChoice(id: id, name: parts.first ?? "", country: parts.count > 1 ? parts[1] : "")
        }
    }

    func setLeague(_ league: SportsLeagueChoice, chosen: Bool, profile: String) {
        set(
            profile: profile, kind: Kind.league, key: String(league.id), chosen: chosen,
            value: [league.name, league.country].joined(separator: Self.separator)
        )
    }

    func teams(profile: String) -> [SportsTeamChoice] {
        rows(profile: profile, kind: Kind.team).compactMap { row in
            guard let id = Int(row.key) else { return nil }
            let parts = row.value.components(separatedBy: Self.separator)
            return SportsTeamChoice(
                id: id,
                name: parts.first ?? "",
                short: parts.count > 1 ? parts[1] : (parts.first ?? ""),
                logo: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil,
                leagueID: parts.count > 3 ? Int(parts[3]) : nil
            )
        }
    }

    func setTeam(_ team: SportsTeamChoice, chosen: Bool, profile: String) {
        let value = [team.name, team.short, team.logo ?? "", team.leagueID.map(String.init) ?? ""]
            .joined(separator: Self.separator)
        set(profile: profile, kind: Kind.team, key: String(team.id), chosen: chosen, value: value)
    }

    func isFollowing(team id: Int, profile: String) -> Bool {
        rows(profile: profile, kind: Kind.team).contains { $0.key == String(id) }
    }

    // MARK: - Flags

    func isSetupDone(profile: String) -> Bool {
        rows(profile: profile, kind: Kind.setupDone).contains { $0.value == "1" }
    }

    func setSetupDone(_ done: Bool, profile: String) {
        set(profile: profile, kind: Kind.setupDone, key: "done", chosen: done, value: "1")
    }

    /// Whether the Sports tab is shown. A setting of the person, not of a profile.
    func showsTab() -> Bool {
        rows(profile: SportsPreference.deviceWide, kind: Kind.showsTab).first.map { $0.value == "1" } ?? true
    }

    func setShowsTab(_ shows: Bool) {
        set(
            profile: SportsPreference.deviceWide,
            kind: Kind.showsTab,
            key: "tab",
            chosen: true,
            value: shows ? "1" : "0"
        )
    }

    // MARK: - Channels the person chose

    /// How many times each channel was chosen for a league, by the channel's id.
    func channelChoices(league: Int, profile: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for row in rows(profile: profile, kind: Kind.channel) where row.key.hasPrefix("\(league)|") {
            result[String(row.key.dropFirst("\(league)|".count))] = Int(row.value) ?? 1
        }
        return result
    }

    func rememberChannel(_ channel: String, league: Int, profile: String) {
        let key = "\(league)|\(channel)"
        let count = (Int(rows(profile: profile, kind: Kind.channel).first { $0.key == key }?.value ?? "0") ?? 0) + 1
        set(profile: profile, kind: Kind.channel, key: key, chosen: true, value: String(count))
    }

    func forgetChannelChoices(profile: String) {
        remove(profile: profile, kind: Kind.channel)
    }

    /// Everything the person chose, so the setup starts again. The key stays.
    func resetSelections(profile: String) {
        for kind in [Kind.league, Kind.team, Kind.setupDone, Kind.channel] {
            remove(profile: profile, kind: kind)
        }
    }

    /// A profile's choices go with the profile.
    func forget(profile: String) {
        for kind in [Kind.league, Kind.team, Kind.setupDone, Kind.channel] {
            remove(profile: profile, kind: kind)
        }
    }

    // MARK: - The key

    /// The key as it is on the record, and whether the person took it out.
    var keyRecord: (blob: Data?, removed: Bool) {
        guard let record = keyRecords().first else { return (nil, false) }
        return (record.encryptedKey, record.removed)
    }

    func setKeyBlob(_ blob: Data?, removed: Bool = false) {
        let records = keyRecords()
        let record = records.first ?? SportsKeyRecord()
        if records.isEmpty {
            context.insert(record)
        }
        record.encryptedKey = blob
        record.removed = removed
        record.updatedAt = .now
        save()
    }

    /// Another device's changes have arrived: screens read again.
    func reloadAfterRemoteChange() {
        revision += 1
    }

    // MARK: - Rows

    /// The rows of a kind, one per key, the newest of any that were written twice, in the order the person chose them.
    private func rows(profile: String, kind: String) -> [SportsPreference] {
        let found = (try? context.fetch(FetchDescriptor<SportsPreference>(
            predicate: #Predicate { $0.profile == profile && $0.kind == kind },
            sortBy: [SortDescriptor(\.position), SortDescriptor(\.updatedAt)]
        ))) ?? []
        var newest: [String: SportsPreference] = [:]
        var stale: [SportsPreference] = []
        for row in found {
            if let other = newest[row.key] {
                if other.updatedAt >= row.updatedAt {
                    stale.append(row)
                } else {
                    stale.append(other)
                    newest[row.key] = row
                }
            } else {
                newest[row.key] = row
            }
        }
        if !stale.isEmpty {
            for row in stale {
                context.delete(row)
            }
            save()
        }
        return found.filter { newest[$0.key] === $0 }
    }

    private func set(profile: String, kind: String, key: String, chosen: Bool, value: String) {
        let existing = (try? context.fetch(FetchDescriptor<SportsPreference>(
            predicate: #Predicate { $0.profile == profile && $0.kind == kind && $0.key == key }
        ))) ?? []
        if !chosen {
            for row in existing {
                context.delete(row)
            }
            save()
            return
        }
        if let row = existing.max(by: { $0.updatedAt < $1.updatedAt }) {
            row.value = value
            row.updatedAt = .now
            for other in existing where other !== row {
                context.delete(other)
            }
        } else {
            let count = (try? context.fetchCount(FetchDescriptor<SportsPreference>(
                predicate: #Predicate { $0.profile == profile && $0.kind == kind }
            ))) ?? 0
            context.insert(SportsPreference(profile: profile, kind: kind, key: key, value: value, position: count))
        }
        save()
    }

    private func remove(profile: String, kind: String) {
        let found = (try? context.fetch(FetchDescriptor<SportsPreference>(
            predicate: #Predicate { $0.profile == profile && $0.kind == kind }
        ))) ?? []
        guard !found.isEmpty else { return }
        for row in found {
            context.delete(row)
        }
        save()
    }

    private func keyRecords() -> [SportsKeyRecord] {
        let found = (try? context.fetch(FetchDescriptor<SportsKeyRecord>(sortBy: [SortDescriptor(
            \.updatedAt,
            order: .reverse
        )]))) ?? []
        // One record is all there should be. A second one, from a device that made its own before the first arrived,
        // goes, the newest standing.
        if found.count > 1 {
            for extra in found.dropFirst() {
                context.delete(extra)
            }
            save()
        }
        return Array(found.prefix(1))
    }

    private func save() {
        try? context.save()
        revision += 1
    }
}
