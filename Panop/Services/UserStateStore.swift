import Foundation
import Observation
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

    static let recentLimit = 50
    /// Played-but-not-favourite rows kept on disk, so recents can reach back past what shows.
    /// Beyond it the oldest go.
    static let retainedPlays = 200

    private let context: ModelContext

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

    /// Notes that a channel was opened.
    func markPlayed(_ key: String, at date: Date = .now) {
        let row = state(for: key) ?? insert(key)
        row.lastPlayedAt = date
        row.updatedAt = date
        trimPlays()
        commit()
    }

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
        if !row.isFavorite, row.lastPlayedAt == .distantPast, row.positionSeconds == 0 {
            context.delete(row)
        }
    }

    /// Keeps the played-only rows to a bounded number, oldest out first. Favourites stay.
    private func trimPlays() {
        let rows = (try? context.fetch(FetchDescriptor<UserContentState>())) ?? []
        let plays = rows
            .filter { !$0.isFavorite && $0.lastPlayedAt > .distantPast }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        for row in plays.dropFirst(Self.retainedPlays) {
            context.delete(row)
        }
    }

    /// Saves, then refreshes what the screens read. If the save fails, what was in memory is
    /// thrown away and re-read, so the screen never shows a state the disk does not have.
    private func commit() {
        do {
            try context.save()
        } catch {
            context.rollback()
        }
        reload()
    }
}
