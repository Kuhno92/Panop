import Foundation
import SwiftData

/// A programme as the screens use it: plain values, so a view never holds a live record.
nonisolated struct ProgrammeSnapshot: Identifiable, Hashable, Sendable {
    var start: Date
    var stop: Date
    var title: String
    var subtitle: String?
    var details: String?

    var id: Date {
        start
    }

    /// On air at `date`: it has begun and not yet ended.
    func isOn(at date: Date) -> Bool {
        start <= date && date < stop
    }

    /// 0 to 1 through the programme, for a progress bar.
    func fraction(at date: Date) -> Double {
        let length = stop.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / length, 0), 1)
    }
}

/// Reads the programme guide for one channel from the catalog.
///
/// One bounded fetch on the `(playlist, channel, start)` index: the channel's own rows, in
/// time order, cut off after a few. Nothing here scans the guide, which holds hundreds of
/// thousands of programmes.
@MainActor
enum GuideLookup {
    /// What is on now and what follows, up to `limit` programmes that have not yet ended.
    ///
    /// - Parameter epgKey: the channel's guide key as stored on the channel (already normalised
    ///   at import), or nil for a channel with no guide, which has nothing to show.
    static func upcoming(
        playlist: String,
        epgKey: String?,
        after now: Date = .now,
        limit: Int,
        in context: ModelContext
    ) -> [ProgrammeSnapshot] {
        guard let key = epgKey, !key.isEmpty, limit > 0 else { return [] }

        // Two reads that each walk the (playlist, channel, start) index from a point, rather than
        // one filtered on the end time: that filter cannot use the index, so SQLite read every
        // programme of the source instead. Measured against a real provider (27,000 programmes)
        // the single filtered read took 25 ms, a whole frame and more, on the main thread for
        // every row that scrolled into view.
        //
        // What is on now began at or before now. The few latest starters are read, and those still
        // running kept, so a long programme overlapped by a short one is not missed.
        let onNow = onNowAll(playlist: playlist, key: key, at: now, in: context)

        var later = FetchDescriptor<EPGProgrammeRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.channelKey == key && $0.start > now },
            sortBy: [SortDescriptor(\.start)]
        )
        later.fetchLimit = Swift.max(limit - onNow.count, 0)
        let following = later.fetchLimit == 0 ? [] : ((try? context.fetch(later)) ?? [])

        return (onNow + following).prefix(limit).map {
            ProgrammeSnapshot(
                start: $0.start,
                stop: $0.stop,
                title: $0.title,
                subtitle: $0.subtitle,
                details: $0.details
            )
        }
    }

    /// What is on at `now` on one channel: begun at or before it and not yet ended, soonest first.
    ///
    /// Nonisolated so the guide reader can use it off the main thread.
    nonisolated static func onNowAll(
        playlist: String,
        key: String,
        at now: Date,
        in context: ModelContext
    ) -> [EPGProgrammeRecord] {
        var earlier = FetchDescriptor<EPGProgrammeRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.channelKey == key && $0.start <= now },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        earlier.fetchLimit = 3
        return ((try? context.fetch(earlier)) ?? []).filter { $0.stop > now }.sorted { $0.start < $1.start }
    }

    /// The one programme on now for a channel, or nil.
    nonisolated static func onNow(
        playlist: String,
        epgKey: String,
        at now: Date,
        in context: ModelContext
    ) -> ProgrammeSnapshot? {
        onNowAll(playlist: playlist, key: epgKey, at: now, in: context).first.map {
            ProgrammeSnapshot(
                start: $0.start,
                stop: $0.stop,
                title: $0.title,
                subtitle: $0.subtitle,
                details: $0.details
            )
        }
    }

    /// Programmes that have ended within the last `days`, newest first, for a channel whose
    /// panel keeps an archive.
    static func aired(
        playlist: String,
        epgKey: String?,
        days: Int,
        before now: Date = .now,
        limit: Int,
        in context: ModelContext
    ) -> [ProgrammeSnapshot] {
        guard let key = epgKey, !key.isEmpty, limit > 0, days > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        var descriptor = FetchDescriptor<EPGProgrammeRecord>(
            predicate: #Predicate {
                $0.playlist == playlist && $0.channelKey == key && $0.start >= cutoff && $0.stop <= now
            },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map {
            ProgrammeSnapshot(
                start: $0.start,
                stop: $0.stop,
                title: $0.title,
                subtitle: $0.subtitle,
                details: $0.details
            )
        }
    }
}
