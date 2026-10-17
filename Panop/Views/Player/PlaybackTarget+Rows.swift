import PanopCore
import PanopPlayback

extension PlaybackTarget {
    /// A snapshot of a list row.
    init(row: CatalogRow) {
        self.init(
            playlist: row.playlist,
            entryID: row.entryID,
            kind: row.kind,
            name: row.name,
            streamURL: row.streamURL,
            remoteID: row.remoteID,
            containerExtension: row.containerExtension,
            archiveDays: row.hasArchive ? row.archiveDays : nil,
            catchupRule: row.catchupRule,
            epgKey: row.epgKey,
            groupKey: row.groupKey
        )
    }

    /// A snapshot of a catalog row, so the player never holds the live record.
    init(entry: CatalogEntryRecord) {
        self.init(
            playlist: entry.playlist,
            entryID: entry.id,
            kind: entry.kind,
            name: entry.name,
            streamURL: entry.streamURL,
            remoteID: entry.remoteID,
            containerExtension: entry.containerExtension,
            archiveDays: entry.hasArchive ? entry.archiveDays : nil,
            catchupRule: entry.catchupRule,
            epgKey: entry.epgKey,
            groupKey: entry.groupKey
        )
    }
}
