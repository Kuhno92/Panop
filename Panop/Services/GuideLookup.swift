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
        var descriptor = FetchDescriptor<EPGProgrammeRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.channelKey == key && $0.stop > now },
            sortBy: [SortDescriptor(\.start)]
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
