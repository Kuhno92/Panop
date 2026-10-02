import Foundation
import Observation
import PanopPlayback
import SwiftData

/// Favourites and recently played, for the screens to read.
///
/// The rows live in the **cloud** container, read with explicit fetches and never `@Query`
/// (docs/adr/0003-two-model-containers.md). What the screens watch is a pair of in-memory
/// values loaded from it, so a toggle updates every row at once and no view binds to the
/// cloud store.
///
/// Rows hold a favourite flag, a last-played time, or both. A row that has neither is deleted:
/// the store should not fill with the ghosts of channels someone once starred and unstarred.
@MainActor
@Observable
final class UserStateStore {
    /// Keys of the favourite channels.
    private(set) var favorites: Set<String> = []
    /// Keys of the channels played most recently, newest first, at most `recentLimit`.
    private(set) var recents: [String] = []

    /// How far into a film or episode someone got, for the ones left unfinished.
    struct Progress: Equatable {
        var position: Double
        var duration: Double

        /// 0 to 1, or nil when the length is not known.
        var fraction: Double? {
            duration > 0 ? min(position / duration, 1) : nil
        }
    }

    private(set) var progress: [String: Progress] = [:]
    /// Keys of the films and episodes seen to the end, or marked as seen.
    private(set) var watched: Set<String> = []
    /// Keys of the entries the person has hidden from the lists.
    private(set) var hidden: Set<String> = []
    /// Categories the person hid, and where they placed the others, by kind (see
    /// `UserStateStore+Categories`).
    /// Counts every change to what the person has watched, marked, hidden or arranged, so a screen
    /// that builds something from it can tell, cheaply, that it is out of date.
    private(set) var revision = 0
    /// What was opened, and when, how often and under which series (see `UserStateStore+Taste`).
    var plays: [String: PlaySignal] = [:]
    var hiddenCategoryNames: [String: Set<String>] = [:]
    var categoryPositions: [String: [String: Int]] = [:]
    private var engines: [String: PlaybackEngineKind] = [:]

    static let recentLimit = 50
    /// Played-but-not-favourite rows kept on disk, so recents can reach back past what shows.
    /// Beyond it the oldest go.
    static let retainedPlays = 200

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    /// The playlist and the entry together, which is what identifies a channel.
    nonisolated static func key(playlist: String, entry: String) -> String {
        "\(playlist)|\(entry)"
    }

    /// The entry id inside a key.
    nonisolated static func entryID(in key: String) -> String {
        key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? key
    }

    func isFavorite(_ key: String) -> Bool {
        favorites.contains(key)
    }

    func toggleFavorite(_ key: String) {
        let row = state(for: key) ?? insert(key)
        row.isFavorite.toggle()
        row.updatedAt = .now
        removeIfEmpty(row)
        commit()
    }

    /// Notes that a channel, film or episode was opened.
    ///
    /// - Parameter parent: for an episode, the key of its series, which is what recommendations are
    ///   drawn from: a person watches shows, not episodes.
    func markPlayed(_ key: String, parent: String? = nil, at date: Date = .now) {
        let row = state(for: key) ?? insert(key)
        row.lastPlayedAt = date
        row.playCount += 1
        if let parent {
            row.parentKey = parent
        }
        row.updatedAt = date
        trimPlays()
        commit()
    }

    /// Films and episodes left part-way, the one watched last first. A point whose title is
    /// missing from the recents (they keep only the latest fifty) comes after the rest.
    var continueWatching: [String] {
        let rank = Dictionary(recents.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return progress.keys.sorted { lhs, rhs in
            let (left, right) = (rank[lhs] ?? .max, rank[rhs] ?? .max)
            return left == right ? lhs < rhs : left < right
        }
    }

    /// Where to resume `key`, or nil to start from the beginning.
    func resumePosition(for key: String) -> Double? {
        progress[key]?.position
    }

    /// Records how far someone has watched. Called now and then during playback and once more
    /// when it stops.
    ///
    /// Not worth keeping: the first moments (nobody resumes ten seconds in), and the last of
    /// the film (the credits). Reaching them clears the point, so the next play starts over.
    func saveProgress(_ key: String, position: Double, duration: Double?, at date: Date = .now) {
        let length = duration ?? 0
        let finished = length > 0 &&
            (position >= length * Self.finishedFraction || length - position < Self.finishedTail)
        let worthKeeping = position >= Self.minimumToKeep && !finished
        guard let row = state(for: key) ?? (worthKeeping || finished ? insert(key) : nil) else { return }
        if finished {
            row.isWatched = true
        }
        row.positionSeconds = worthKeeping ? position : 0
        row.durationSeconds = worthKeeping ? length : 0
        row.updatedAt = date
        removeIfEmpty(row)
        commit()
    }

    func isHidden(_ key: String) -> Bool {
        hidden.contains(key)
    }

    /// Hides an entry from every list, or shows it again. Its favourite, history and resume point
    /// are kept, so showing it again loses nothing.
    func setHidden(_ isHidden: Bool, for key: String, at date: Date = .now) {
        guard let row = state(for: key) ?? (isHidden ? insert(key) : nil) else { return }
        row.isHidden = isHidden
        row.updatedAt = date
        removeIfEmpty(row)
        commit()
    }

    func isWatched(_ key: String) -> Bool {
        watched.contains(key)
    }

    /// Marks a film or episode as seen, or not. Marking it seen drops any resume point, since
    /// there is nothing left to resume.
    func setWatched(_ isWatched: Bool, for key: String, at date: Date = .now) {
        guard let row = state(for: key) ?? (isWatched ? insert(key) : nil) else { return }
        row.isWatched = isWatched
        if isWatched {
            row.positionSeconds = 0
            row.durationSeconds = 0
        }
        row.updatedAt = date
        removeIfEmpty(row)
        commit()
    }

    /// Past this share of the way through, it counts as watched.
    static let finishedFraction = 0.95
    /// Or with less than this many seconds left.
    static let finishedTail = 30.0
    /// Before this many seconds in there is nothing to come back to.
    static let minimumToKeep = 10.0

    /// Drops everything about a playlist that has been deleted.
    func forget(playlist: String) {
        let prefix = Self.key(playlist: playlist, entry: "")
        let rows = (try? context.fetch(FetchDescriptor<UserContentState>())) ?? []
        for row in rows where row.streamID.hasPrefix(prefix) {
            context.delete(row)
        }
        commit()
    }

    func reload() {
        let rows = (try? context.fetch(FetchDescriptor<UserContentState>())) ?? []
        favorites = Set(rows.filter(\.isFavorite).map(\.streamID))
        progress = Dictionary(
            rows.filter { $0.positionSeconds > 0 }.map {
                ($0.streamID, Progress(position: $0.positionSeconds, duration: $0.durationSeconds))
            },
            uniquingKeysWith: { first, _ in first }
        )
        watched = Set(rows.filter(\.isWatched).map(\.streamID))
        hidden = Set(rows.filter(\.isHidden).map(\.streamID))
        plays = Dictionary(
            rows.filter { $0.lastPlayedAt > .distantPast }.map {
                ($0.streamID, PlaySignal(lastPlayedAt: $0.lastPlayedAt, times: $0.playCount, parentKey: $0.parentKey))
            },
            uniquingKeysWith: { first, _ in first }
        )
        loadCategoryPreferences()
        engines = Dictionary(
            rows.compactMap { row in PlaybackEngineKind(rawValue: row.rememberedEngine).map { (row.streamID, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        recents = rows
            .filter { $0.lastPlayedAt > .distantPast }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .prefix(Self.recentLimit)
            .map(\.streamID)
    }

    // MARK: - Rows

    private func state(for key: String) -> UserContentState? {
        var descriptor = FetchDescriptor<UserContentState>(predicate: #Predicate { $0.streamID == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func insert(_ key: String) -> UserContentState {
        let row = UserContentState(streamID: key)
        context.insert(row)
        return row
    }

    private func removeIfEmpty(_ row: UserContentState) {
        if !row.isFavorite, row.lastPlayedAt == .distantPast, row.positionSeconds == 0, row.rememberedEngine.isEmpty,
           !row.isWatched, !row.isHidden
        {
            context.delete(row)
        }
    }

    /// Keeps the played-only rows to a bounded number, oldest out first. Favourites stay.
    private func trimPlays() {
        let rows = (try? context.fetch(FetchDescriptor<UserContentState>())) ?? []
        let plays = rows
            .filter { !$0.isFavorite && !$0.isHidden && !$0.isWatched && $0.lastPlayedAt > .distantPast }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        for row in plays.dropFirst(Self.retainedPlays) {
            context.delete(row)
        }
    }

    /// Saves, then refreshes what the screens read. If the save fails, what was in memory is
    /// thrown away and re-read, so the screen never shows a state the disk does not have.
    func commit() {
        revision += 1
        do {
            try context.save()
        } catch {
            context.rollback()
        }
        reload()
    }
}

/// What the player consults to try, first, the engine that worked last time.
@MainActor
protocol EngineMemory: AnyObject {
    func remembered(for key: String) -> PlaybackEngineKind?
    func remember(_ engine: PlaybackEngineKind, for key: String)
    func forget(for key: String)
}

extension UserStateStore: EngineMemory {
    func remembered(for key: String) -> PlaybackEngineKind? {
        engines[key]
    }

    func remember(_ engine: PlaybackEngineKind, for key: String) {
        guard engines[key] != engine else { return }
        let row = state(for: key) ?? insert(key)
        row.rememberedEngine = engine.rawValue
        commit()
    }

    func forget(for key: String) {
        guard engines[key] != nil, let row = state(for: key) else { return }
        row.rememberedEngine = ""
        removeIfEmpty(row)
        commit()
    }
}
