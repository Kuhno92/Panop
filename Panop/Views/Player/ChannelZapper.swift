import Foundation
import PanopCore
import SwiftData

/// The channel before or after the one that plays, for switching with the remote's Up and Down.
///
/// In the order the Live list has by default (the provider's number, then the name), within the playlist the channel is
/// from, skipping what the person hid and, when the list is grouped by guide, the extra versions of a channel. Past the
/// last channel it goes round to the first. Two bounded fetches at most, each ordered by the indexed sort column: a
/// catalog of 80,000 channels costs no more than one of 80.
enum ChannelZapper {
    /// Candidates looked at before giving up: the hidden ones in a row, and the dividers some lists have between
    /// groups.
    private static let reach = 40

    @MainActor
    static func neighbour(
        of target: PlaybackTarget,
        step: Int,
        hidden: Set<String>,
        leadsOnly: Bool,
        in context: ModelContext
    ) -> CatalogRow? {
        let playlist = target.playlist
        let id = target.entryID
        let live = MediaKind.live.rawValue
        var here = FetchDescriptor<CatalogEntryRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.id == id }
        )
        here.fetchLimit = 1
        guard let current = (try? context.fetch(here))?.first else { return nil }
        let forward = step > 0

        func usable(_ rows: [CatalogEntryRecord]) -> CatalogRow? {
            rows.lazy
                .filter { $0.id != id && !hidden.contains(UserStateStore.key(playlist: $0.playlist, entry: $0.id)) }
                .map(CatalogRow.init)
                .first
        }

        // After (or before) this one; then, from the other end, so the last goes round to the first.
        if let number = current.sortNumber {
            let after: FetchDescriptor<CatalogEntryRecord> = forward
                ? FetchDescriptor(
                    predicate: #Predicate {
                        $0.playlist == playlist && $0.kindRaw == live && $0.sortNumber != nil
                            && ($0.sortNumber ?? 0) > number && (!leadsOnly || $0.isGuideLead)
                    },
                    sortBy: [SortDescriptor(\.sortNumber), SortDescriptor(\.nameKey, comparator: .lexical)]
                )
                : FetchDescriptor(
                    predicate: #Predicate {
                        $0.playlist == playlist && $0.kindRaw == live && $0.sortNumber != nil
                            && ($0.sortNumber ?? 0) < number && (!leadsOnly || $0.isGuideLead)
                    },
                    sortBy: [SortDescriptor(\.sortNumber, order: .reverse), SortDescriptor(\.nameKey, order: .reverse)]
                )
            if let row = fetch(after, in: context).flatMap(usable) {
                return row
            }
            let wrap: FetchDescriptor<CatalogEntryRecord> = FetchDescriptor(
                predicate: #Predicate {
                    $0.playlist == playlist && $0.kindRaw == live && $0.sortNumber != nil
                        && (!leadsOnly || $0.isGuideLead)
                },
                sortBy: [SortDescriptor(\.sortNumber, order: forward ? .forward : .reverse)]
            )
            return fetch(wrap, in: context).flatMap(usable)
        }

        // A list with no numbers is ordered by name.
        let key = current.nameKey
        let after: FetchDescriptor<CatalogEntryRecord> = forward
            ? FetchDescriptor(
                predicate: #Predicate {
                    $0.playlist == playlist && $0.kindRaw == live && $0.nameKey > key && (!leadsOnly || $0.isGuideLead)
                },
                sortBy: [SortDescriptor(\.nameKey, comparator: .lexical), SortDescriptor(\.id, comparator: .lexical)]
            )
            : FetchDescriptor(
                predicate: #Predicate {
                    $0.playlist == playlist && $0.kindRaw == live && $0.nameKey < key && (!leadsOnly || $0.isGuideLead)
                },
                sortBy: [
                    SortDescriptor(\.nameKey, comparator: .lexical, order: .reverse),
                    SortDescriptor(\.id, comparator: .lexical, order: .reverse)
                ]
            )
        if let row = fetch(after, in: context).flatMap(usable) {
            return row
        }
        let wrap: FetchDescriptor<CatalogEntryRecord> = FetchDescriptor(
            predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == live && (!leadsOnly || $0.isGuideLead) },
            sortBy: [SortDescriptor(\.nameKey, comparator: .lexical, order: forward ? .forward : .reverse)]
        )
        return fetch(wrap, in: context).flatMap(usable)
    }

    @MainActor
    private static func fetch(
        _ descriptor: FetchDescriptor<CatalogEntryRecord>,
        in context: ModelContext
    ) -> [CatalogEntryRecord]? {
        var bounded = descriptor
        bounded.fetchLimit = reach
        return try? context.fetch(bounded)
    }
}
