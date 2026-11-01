import Foundation
import SwiftData

/// Everything in the cloud container as plain values, so it can be put back after iCloud has been wiped.
///
/// Rows are matched by their natural key (a playlist's id, a profile's stream, a category's kind and name...), never by
/// SwiftData identity, so `insertMissing` can run any number of times and never makes a second copy of a row.
@MainActor
struct SyncedSnapshot: Codable, Equatable {
    struct Playlist: Codable, Equatable {
        var id: String
        var name: String
        var kindRaw: String
        var displayHost: String
        var localFileName: String?
        var createdAt: Date
        var sortOrder: Int
        var includesVOD: Bool
        var encryptedLogin: Data?
    }

    struct State: Codable, Equatable {
        var streamID: String
        var isFavorite: Bool
        var positionSeconds: Double
        var durationSeconds: Double
        var updatedAt: Date
        var lastPlayedAt: Date
        var rememberedEngine: String
        var preferredVariantID: String
        var isWatched: Bool
        var isHidden: Bool
        var playCount: Int
        var parentKey: String
        var profile: String
    }

    struct Category: Codable, Equatable {
        var kindRaw: String
        var name: String
        var isHidden: Bool
        var position: Int
        var profile: String
    }

    struct SportsChoice: Codable, Equatable {
        var profile: String
        var kind: String
        var key: String
        var value: String
        var position: Int
        var updatedAt: Date
    }

    /// The sports key and the VPN configuration, each one record at most.
    struct Secret: Codable, Equatable {
        var blob: Data?
        var removed: Bool
        var updatedAt: Date
    }

    var playlists: [Playlist] = []
    var states: [State] = []
    var categories: [Category] = []
    var sports: [SportsChoice] = []
    var sportsKey: Secret?
    var vpnConfig: Secret?

    var isEmpty: Bool {
        self == SyncedSnapshot()
    }

    // MARK: - Reading

    static func capture(from context: ModelContext) -> SyncedSnapshot {
        var snapshot = SyncedSnapshot()
        snapshot.playlists = ((try? context.fetch(FetchDescriptor<PlaylistRecord>())) ?? []).map {
            Playlist(
                id: $0.id, name: $0.name, kindRaw: $0.kindRaw, displayHost: $0.displayHost,
                localFileName: $0.localFileName, createdAt: $0.createdAt, sortOrder: $0.sortOrder,
                includesVOD: $0.includesVOD, encryptedLogin: $0.encryptedLogin
            )
        }
        snapshot.states = ((try? context.fetch(FetchDescriptor<UserContentState>())) ?? []).map {
            State(
                streamID: $0.streamID, isFavorite: $0.isFavorite, positionSeconds: $0.positionSeconds,
                durationSeconds: $0.durationSeconds, updatedAt: $0.updatedAt, lastPlayedAt: $0.lastPlayedAt,
                rememberedEngine: $0.rememberedEngine, preferredVariantID: $0.preferredVariantID,
                isWatched: $0.isWatched, isHidden: $0.isHidden, playCount: $0.playCount,
                parentKey: $0.parentKey, profile: $0.profile
            )
        }
        snapshot.categories = ((try? context.fetch(FetchDescriptor<CategoryPreference>())) ?? []).map {
            Category(
                kindRaw: $0.kindRaw,
                name: $0.name,
                isHidden: $0.isHidden,
                position: $0.position,
                profile: $0.profile
            )
        }
        snapshot.sports = ((try? context.fetch(FetchDescriptor<SportsPreference>())) ?? []).map {
            SportsChoice(
                profile: $0.profile, kind: $0.kind, key: $0.key, value: $0.value, position: $0.position,
                updatedAt: $0.updatedAt
            )
        }
        snapshot.sportsKey = (try? context.fetch(FetchDescriptor<SportsKeyRecord>()))?.first.map {
            Secret(blob: $0.encryptedKey, removed: $0.removed, updatedAt: $0.updatedAt)
        }
        snapshot.vpnConfig = (try? context.fetch(FetchDescriptor<VPNConfigRecord>()))?.first.map {
            Secret(blob: $0.encryptedConfig, removed: $0.removed, updatedAt: $0.updatedAt)
        }
        return snapshot
    }

    // MARK: - Writing

    /// Deletes every row and inserts them again as new ones. Whatever mirroring does with a wiped zone (empties this
    /// device, or keeps it), the rows are then new writes, which are exported to the zone iCloud makes again.
    func rewrite(in context: ModelContext) {
        deleteAll(in: context)
        try? context.save()
        insertMissing(into: context)
    }

    /// Puts back what is not there, by natural key.
    /// - Returns: how many rows were inserted.
    @discardableResult
    func insertMissing(into context: ModelContext) -> Int {
        var inserted = 0
        let playlistIDs = Set(((try? context.fetch(FetchDescriptor<PlaylistRecord>())) ?? []).map(\.id))
        for item in playlists where !playlistIDs.contains(item.id) {
            let record = PlaylistRecord(
                id: item.id, name: item.name, kind: PlaylistKind(rawValue: item.kindRaw) ?? .xtream,
                displayHost: item.displayHost, localFileName: item.localFileName, createdAt: item.createdAt,
                sortOrder: item.sortOrder, includesVOD: item.includesVOD
            )
            record.encryptedLogin = item.encryptedLogin
            context.insert(record)
            inserted += 1
        }
        let stateKeys = Set(((try? context.fetch(FetchDescriptor<UserContentState>())) ?? [])
            .map { "\($0.profile)\u{1}\($0.streamID)" })
        for item in states where !stateKeys.contains("\(item.profile)\u{1}\(item.streamID)") {
            let row = UserContentState(
                streamID: item.streamID, isFavorite: item.isFavorite, positionSeconds: item.positionSeconds,
                durationSeconds: item.durationSeconds, updatedAt: item.updatedAt, lastPlayedAt: item.lastPlayedAt
            )
            row.rememberedEngine = item.rememberedEngine
            row.preferredVariantID = item.preferredVariantID
            row.isWatched = item.isWatched
            row.isHidden = item.isHidden
            row.playCount = item.playCount
            row.parentKey = item.parentKey
            row.profile = item.profile
            context.insert(row)
            inserted += 1
        }
        let categoryKeys = Set(((try? context.fetch(FetchDescriptor<CategoryPreference>())) ?? [])
            .map { "\($0.profile)\u{1}\($0.kindRaw)\u{1}\($0.name)" })
        for item in categories where !categoryKeys.contains("\(item.profile)\u{1}\(item.kindRaw)\u{1}\(item.name)") {
            let row = CategoryPreference(
                kindRaw: item.kindRaw,
                name: item.name,
                isHidden: item.isHidden,
                position: item.position
            )
            row.profile = item.profile
            context.insert(row)
            inserted += 1
        }
        let sportsKeys = Set(((try? context.fetch(FetchDescriptor<SportsPreference>())) ?? [])
            .map { "\($0.profile)\u{1}\($0.kind)\u{1}\($0.key)" })
        for item in sports where !sportsKeys.contains("\(item.profile)\u{1}\(item.kind)\u{1}\(item.key)") {
            context.insert(SportsPreference(
                profile: item.profile, kind: item.kind, key: item.key, value: item.value, position: item.position,
                at: item.updatedAt
            ))
            inserted += 1
        }
        if let item = sportsKey, ((try? context.fetchCount(FetchDescriptor<SportsKeyRecord>())) ?? 0) == 0 {
            context.insert(SportsKeyRecord(encryptedKey: item.blob, removed: item.removed, at: item.updatedAt))
            inserted += 1
        }
        if let item = vpnConfig, ((try? context.fetchCount(FetchDescriptor<VPNConfigRecord>())) ?? 0) == 0 {
            context.insert(VPNConfigRecord(encryptedConfig: item.blob, removed: item.removed, at: item.updatedAt))
            inserted += 1
        }
        try? context.save()
        return inserted
    }

    private func deleteAll(in context: ModelContext) {
        try? context.delete(model: PlaylistRecord.self)
        try? context.delete(model: UserContentState.self)
        try? context.delete(model: CategoryPreference.self)
        try? context.delete(model: SportsPreference.self)
        try? context.delete(model: SportsKeyRecord.self)
        try? context.delete(model: VPNConfigRecord.self)
    }

    // MARK: - On disk

    /// Kept on disk from before the wipe until the restore has been confirmed, so a quit or a crash in between cannot
    /// lose the data (it holds provider logins as the records do: not backed up, and removed as soon as it is done).
    static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SyncResetSnapshot.json")
    }

    func save(to url: URL = SyncedSnapshot.file) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(excluded)
    }

    static func load(from url: URL = SyncedSnapshot.file) -> SyncedSnapshot? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SyncedSnapshot.self, from: $0) }
    }

    static func discard(at url: URL = SyncedSnapshot.file) {
        try? FileManager.default.removeItem(at: url)
    }
}
