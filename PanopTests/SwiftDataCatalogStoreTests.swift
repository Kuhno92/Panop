import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import PanopEPG
import SwiftData
import Testing

private let playlist = "p1"
private let other = "p2"

@Suite("SwiftData catalog store")
struct SwiftDataCatalogStoreTests {
    // MARK: - Entries

    @Test
    func `reports inserted, unchanged and updated rows`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store

        let rows = (0 ..< 10).map { entry("live:\($0)") }
        #expect(try await store.upsertEntries(rows, playlist: playlist) == UpsertSummary(inserted: 10))
        #expect(try await store.upsertEntries(rows, playlist: playlist) == UpsertSummary(unchanged: 10))

        var changed = rows
        changed[3].name = "Renamed"
        changed[7].iconURL = "http://img/7.png"
        #expect(try await store.upsertEntries(changed, playlist: playlist) == UpsertSummary(updated: 2, unchanged: 8))
    }

    /// The claim the whole "unchanged refresh writes nothing" design rests on: a
    /// record that already matches is not dirtied, so the context has nothing to save.
    @Test @MainActor
    func `applying an identical entry leaves the record clean`() throws {
        let container = try PanopContainers.makeCatalog(inMemory: true)
        let context = ModelContext(container)
        let source = CatalogEntry(
            id: "live:1", kind: .live, name: "One", groupID: "g", groupName: "G", iconURL: "u",
            epgKey: "k", streamURL: "s", remoteID: "1", containerExtension: "ts", sortNumber: 1,
            hasArchive: true, archiveDays: 3, addedAt: Date(timeIntervalSince1970: 10), rating: 4.5, plot: "p"
        )
        let record = CatalogEntryRecord(playlist: playlist, entry: source)
        context.insert(record)
        try context.save()
        #expect(!context.hasChanges)

        #expect(record.apply(source) == false)
        #expect(!context.hasChanges, "an unchanged entry dirtied the context, so every refresh would write every row")

        var edited = source
        edited.name = "Two"
        #expect(record.apply(edited))
        #expect(context.hasChanges)
    }

    @Test
    func `a repeated id in one batch is one row`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }

        let summary = try await catalog.store.upsertEntries(
            [entry("live:1", name: "First"), entry("live:1", name: "Second")],
            playlist: playlist
        )

        #expect(summary.inserted == 1)
        #expect(try await catalog.store.entryCount(kind: .live, playlist: playlist) == 1)
    }

    @Test
    func `playlists are isolated`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store

        _ = try await store.upsertEntries([entry("live:1"), entry("live:2")], playlist: playlist)
        _ = try await store.upsertEntries([entry("live:1")], playlist: other)

        #expect(try await store.entryCount(kind: .live, playlist: playlist) == 2)
        #expect(try await store.entryCount(kind: .live, playlist: other) == 1)

        try await store.removeEntries(ids: ["live:1"], playlist: playlist)
        #expect(try await store.entryCount(kind: .live, playlist: playlist) == 1)
        #expect(try await store.entryCount(kind: .live, playlist: other) == 1)
    }

    @Test
    func `counts and listings are per kind`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store
        _ = try await store.upsertEntries(
            [entry("live:1"), entry("live:2"), entry("movie:1", kind: .movie), entry("series:1", kind: .series)],
            playlist: playlist
        )

        #expect(try await store.entryCount(kind: .live, playlist: playlist) == 2)
        #expect(try await store.entryCount(kind: .movie, playlist: playlist) == 1)
        #expect(try await store.entryIDs(kind: .movie, playlist: playlist, after: nil, limit: 10) == ["movie:1"])
    }

    // MARK: - No duplicates

    /// Uniqueness is the store's job, not the database's (see CatalogRecords.swift).
    /// Every way rows can arrive twice must still end as one row.
    @Test
    func `overlapping and repeated batches never produce duplicate rows`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store
        let day = Date(timeIntervalSince1970: 1_790_640_000)

        // Overlapping id ranges, repeats inside a batch, and an id that changes kind.
        _ = try await store.upsertEntries((0 ..< 300).map { entry("live:\($0)") }, playlist: playlist)
        _ = try await store.upsertEntries((200 ..< 500).map { entry("live:\($0)") }, playlist: playlist)
        _ = try await store.upsertEntries(
            (0 ..< 50).flatMap { [entry("live:\($0)"), entry("live:\($0)")] },
            playlist: playlist
        )
        _ = try await store.upsertEntries([entry("live:7", kind: .movie)], playlist: playlist)

        /// The same programmes arriving again, across channel case, in overlapping batches.
        func slot(_ channel: String, _ hour: Int) -> EPGProgramme {
            let start = day.addingTimeInterval(TimeInterval(hour * 3600))
            return EPGProgramme(channelID: channel, start: start, stop: start.addingTimeInterval(3600), title: "T")
        }
        _ = try await store.upsertProgrammes((0 ..< 30).map { slot("ARD.de", $0) }, playlist: playlist)
        _ = try await store.upsertProgrammes((20 ..< 50).map { slot("ard.de", $0) }, playlist: playlist)
        _ = try await store.upsertProgrammes(
            (0 ..< 10).flatMap { [slot("ard.de", $0), slot("ARD.DE", $0)] },
            playlist: playlist
        )

        try await MainActor.run {
            let context = ModelContext(catalog.container)
            let entries = try context.fetch(FetchDescriptor<CatalogEntryRecord>())
            #expect(entries.count == 500)
            #expect(Set(entries.map(\.id)).count == 500, "an id was stored twice")
            #expect(entries.first { $0.id == "live:7" }?.kind == .movie)

            let programmes = try context.fetch(FetchDescriptor<EPGProgrammeRecord>())
            #expect(programmes.count == 50)
            #expect(Set(programmes.map { "\($0.channelKey)|\($0.start.timeIntervalSince1970)" }).count == 50)
        }
    }

    // MARK: - Paging

    /// The importer resumes each page from the last id it saw. That is only
    /// correct if the sort and the `>` comparison agree, and on SQLite they can
    /// disagree (a localised default collation, letter case, punctuation). Every
    /// id must appear exactly once.
    @Test
    func `paging visits every id exactly once, including awkward ones`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store

        let ids = [
            "a", "B", "b", "A", "ä", "Ä", "é", "e", "E", "z", "Z", "10", "9", "1", "_x", "-x", ".x", "x y", "x_y",
            "x-y",
            "m3u:00ab", "m3u:00AB", "live:1", "live:10", "live:9", "日本", "🙂", "ａ", "\u{FF5E}", "ß", "ss", "İ", "i", "I"
        ]
        _ = try await store.upsertEntries(ids.map { entry($0) }, playlist: playlist)

        for pageSize in [1, 3, 7, 100] {
            var seen: [String] = []
            var cursor: String?
            while true {
                let page = try await store.entryIDs(kind: .live, playlist: playlist, after: cursor, limit: pageSize)
                guard let last = page.last else { break }
                seen += page
                cursor = last
            }
            #expect(seen.count == ids.count, "page size \(pageSize): \(seen.count) of \(ids.count) ids")
            #expect(Set(seen) == Set(ids), "page size \(pageSize) skipped or repeated an id")
        }
    }

    /// For the ids this app actually generates (ASCII) the order must also be
    /// plain binary, since the in-memory store and the docs promise it.
    @Test
    func `ASCII ids page in binary order`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let ids = ["live:9", "live:10", "live:1", "Live:2", "movie:5", "live:_", "live:a", "live:B", "live:b"]
        _ = try await catalog.store.upsertEntries(ids.map { entry($0) }, playlist: playlist)

        let paged = try await catalog.store.entryIDs(kind: .live, playlist: playlist, after: nil, limit: 100)

        let expected = ids.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        #expect(paged == expected)
    }

    // MARK: - Categories

    @Test
    func `categories upsert, list and remove per kind`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store

        try await store.upsertCategories([
            CatalogCategory(id: "1", kind: .live, name: "News"),
            CatalogCategory(id: "2", kind: .live, name: "Sport"),
            CatalogCategory(id: "1", kind: .movie, name: "Action")
        ], playlist: playlist)
        // Same ids again, one renamed: still three rows.
        try await store.upsertCategories([CatalogCategory(id: "2", kind: .live, name: "Sports")], playlist: playlist)

        #expect(try await store.categoryIDs(kind: .live, playlist: playlist).sorted() == ["1", "2"])
        #expect(try await store.categoryIDs(kind: .movie, playlist: playlist) == ["1"])

        try await store.removeCategories(ids: ["1"], kind: .live, playlist: playlist)
        #expect(try await store.categoryIDs(kind: .live, playlist: playlist) == ["2"])
        #expect(try await store.categoryIDs(kind: .movie, playlist: playlist) == ["1"])
    }

    // MARK: - Guide

    private func programme(_ channel: String, hour: Int, title: String = "T") -> EPGProgramme {
        let start = Date(timeIntervalSince1970: 1_790_640_000 + TimeInterval(hour * 3600))
        return EPGProgramme(channelID: channel, start: start, stop: start.addingTimeInterval(3600), title: title)
    }

    @Test
    func `programmes upsert and dedupe across channel case`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store
        let day = Date(timeIntervalSince1970: 1_790_640_000)

        let first = try await store.upsertProgrammes(
            [programme("ARD.de", hour: 0), programme("ARD.de", hour: 1)],
            playlist: playlist
        )
        #expect(first == UpsertSummary(inserted: 2))

        // Same programmes with the channel written in another case. They are the
        // same rows (no inserts); the record only refreshes the id as written.
        let second = try await store.upsertProgrammes(
            [programme("ard.DE", hour: 0), programme("ard.de", hour: 1, title: "Changed")],
            playlist: playlist
        )
        #expect(second.inserted == 0)
        #expect(second.updated == 2)
        #expect(try await store.programmeCount(playlist: playlist, endingAfter: day) == 2)
    }

    @Test
    func `programme starts are read per channel`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store
        let day = Date(timeIntervalSince1970: 1_790_640_000)

        var rows: [EPGProgramme] = []
        for channel in ["a.de", "B.de", "ard.de"] {
            for hour in 0 ..< 6 {
                rows.append(programme(channel, hour: hour))
            }
        }
        _ = try await store.upsertProgrammes(rows, playlist: playlist)

        let starts = try await store.programmeStarts(playlist: playlist, channelKey: "b.de", endingAfter: day)
        #expect(Set(starts) == Set((0 ..< 6).map { day.addingTimeInterval(TimeInterval($0 * 3600)) }))
        #expect(try await store.programmeStarts(playlist: playlist, channelKey: "nope", endingAfter: day).isEmpty)

        // Hour 3 ends at hour 4, so only hours 4 and 5 are still current after it.
        let late = try await store.programmeStarts(
            playlist: playlist,
            channelKey: "b.de",
            endingAfter: day.addingTimeInterval(4 * 3600)
        )
        #expect(late.count == 2)
    }

    @Test
    func `removing programmes by channel and start`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store
        let day = Date(timeIntervalSince1970: 1_790_640_000)

        _ = try await store.upsertProgrammes((0 ..< 6).map { programme("ard.de", hour: $0) }, playlist: playlist)
        _ = try await store.upsertProgrammes([programme("zdf.de", hour: 5)], playlist: playlist)

        try await store.removeProgrammes(
            playlist: playlist,
            channelKey: "ard.de",
            starts: [day.addingTimeInterval(5 * 3600), day.addingTimeInterval(4 * 3600)]
        )
        #expect(try await store.programmeCount(playlist: playlist, endingAfter: day) == 5)
        // The other channel's programme at the same start time is untouched.
        #expect(try await store.programmeStarts(playlist: playlist, channelKey: "zdf.de", endingAfter: day).count == 1)
    }

    @Test
    func `removing programmes by end time`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store
        let day = Date(timeIntervalSince1970: 1_790_640_000)
        _ = try await store.upsertProgrammes((0 ..< 6).map { programme("ard.de", hour: $0) }, playlist: playlist)

        // Hour 1 ends at hour 2: "at or before" removes hours 0 and 1.
        let removed = try await store.removeProgrammes(
            endedBefore: day.addingTimeInterval(2 * 3600),
            playlist: playlist
        )
        #expect(removed == 2)
        #expect(try await store.programmeCount(playlist: playlist, endingAfter: day) == 4)
    }

    @Test
    func `guide channel ids are listed per playlist`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await catalog.store.upsertEPGChannels(
            [EPGChannel(id: "ard.de"), EPGChannel(id: "zdf.de")],
            playlist: playlist
        )
        try await catalog.store.upsertEPGChannels([EPGChannel(id: "other.de")], playlist: other)

        #expect(try await catalog.store.epgChannelIDs(playlist: playlist).sorted() == ["ard.de", "zdf.de"])
    }

    @Test
    func `a programme ending exactly at the cutoff counts as ended`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let day = Date(timeIntervalSince1970: 1_790_640_000)
        _ = try await catalog.store.upsertProgrammes([programme("a", hour: 0)], playlist: playlist)
        let cutoff = day.addingTimeInterval(3600)

        // It must be in neither set: not counted as current, and removed as expired.
        #expect(try await catalog.store.programmeCount(playlist: playlist, endingAfter: cutoff) == 0)
        #expect(try await catalog.store.removeProgrammes(endedBefore: cutoff, playlist: playlist) == 1)
    }

    @Test
    func `guide channels upsert idempotently`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let channels = [EPGChannel(id: "ard.de", displayNames: ["ARD", "Das Erste"], iconURL: "u")]

        try await catalog.store.upsertEPGChannels(channels, playlist: playlist)
        try await catalog.store.upsertEPGChannels(channels, playlist: playlist)

        try await MainActor.run {
            let context = ModelContext(catalog.container)
            let records = try context.fetch(FetchDescriptor<EPGChannelRecord>())
            #expect(records.count == 1)
            #expect(records.first?.displayNames == ["ARD", "Das Erste"])
        }
    }

    // MARK: - State

    @Test
    func `sync state round-trips and updates in place`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let store = catalog.store
        #expect(try await store.syncState(playlist: playlist) == nil)

        let first = SyncState(importCounter: 1, digest: "abc", lastCompleted: Date(timeIntervalSince1970: 5))
        try await store.saveSyncState(first, playlist: playlist)
        #expect(try await store.syncState(playlist: playlist) == first)

        let second = SyncState(importCounter: 2, digest: nil, lastCompleted: nil)
        try await store.saveSyncState(second, playlist: playlist)
        #expect(try await store.syncState(playlist: playlist) == second)
        #expect(try await store.syncState(playlist: other) == nil)
    }
}
