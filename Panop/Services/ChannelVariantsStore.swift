import Foundation
import Observation
import PanopCore
import SwiftData
import SwiftUI

/// Whether the Live TV list shows one channel per guide: channels that share a guide key (the HD, SD and 4K versions of
/// one channel, say) collapse into the first of them, and the others are chosen from it.
nonisolated enum ChannelGrouping {
    static let key = "groupsByGuide"
    /// On unless the person turns it off: a playlist with the same channel in HD and SD lists it once.
    static let isOnByDefault = true
}

/// The other versions of a channel: every live channel of its playlist that has the same guide key, read in the
/// background and kept ready, the way `GuideNowStore` keeps what is on.
///
/// A row never reads the catalog itself. It asks here, which answers from memory at once (nothing, until the read
/// finishes), and the lookups wanted at about the same moment go in one read on a background thread.
@MainActor
@Observable
final class ChannelVariantsStore {
    /// Wait before reading, so a row that is only passing is gone by then.
    static let settleDelay = Duration.milliseconds(120)
    /// Shared by every list, so a channel is read once however many rows ask.
    static let shared = ChannelVariantsStore()
    /// More versions than this of one channel is not a choice, it is a mistake in a playlist.
    nonisolated static let limit = 24

    private var entries: [String: [CatalogRow]] = [:]
    @ObservationIgnored private var wanted: Set<GuideKey> = []
    @ObservationIgnored private var inFlight: Set<GuideKey> = []
    @ObservationIgnored private var batch: Task<Void, Never>?
    @ObservationIgnored private var reader: VariantsReader?
    @ObservationIgnored private var generation = 0

    /// The channels that share this one's guide key, in the provider's order, this one among them; nil until read, and
    /// for
    /// a channel with no guide key. Reads memory only.
    func variants(playlist: String, groupKey: String?) -> [CatalogRow]? {
        guard let groupKey, !groupKey.isEmpty else { return nil }
        return entries[Self.id(playlist, groupKey)]
    }

    /// Asks for a channel's versions. Cheap, and folded with the others asked for at about the same moment.
    func request(playlist: String, groupKey: String?, in container: ModelContainer) {
        guard let groupKey, !groupKey.isEmpty, entries[Self.id(playlist, groupKey)] == nil else { return }
        // `GuideKey`'s second part is the group key here.
        let key = GuideKey(playlist: playlist, epgKey: groupKey)
        guard !inFlight.contains(key) else { return }
        wanted.insert(key)
        if reader == nil {
            reader = VariantsReader(container: container)
        }
        guard batch == nil, let reader else { return }
        let current = generation
        batch = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            let keys = wanted
            wanted = []
            inFlight.formUnion(keys)
            let found = await reader.read(keys)
            guard current == generation else { return }
            var updated = entries
            for (key, rows) in found {
                updated[Self.id(key.playlist, key.epgKey)] = rows
            }
            entries = updated
            inFlight.subtract(keys)
            batch = nil
            if let any = wanted.first {
                request(playlist: any.playlist, groupKey: any.epgKey, in: container)
            }
        }
    }

    /// A row that scrolled away before its answer was wanted: it need not be read.
    func withdraw(playlist: String, groupKey: String?) {
        guard let groupKey else { return }
        wanted.remove(GuideKey(playlist: playlist, epgKey: groupKey))
    }

    /// Forgets everything, for when the catalog has been replaced by an import.
    func reset() {
        generation += 1
        entries = [:]
        wanted = []
        inFlight = []
        batch?.cancel()
        batch = nil
    }

    private static func id(_ playlist: String, _ epgKey: String) -> String {
        "\(playlist)|\(epgKey)"
    }
}

/// Reads the versions off the main thread, in a context of its own so it sees what an import has just written.
private actor VariantsReader {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func read(_ keys: Set<GuideKey>) -> [GuideKey: [CatalogRow]] {
        let context = ModelContext(container)
        let live = MediaKind.live.rawValue
        var found: [GuideKey: [CatalogRow]] = [:]
        for key in keys {
            let playlist = key.playlist
            let groupKey: String? = key.epgKey
            var descriptor = FetchDescriptor<CatalogEntryRecord>(
                predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == live && $0.groupKey == groupKey },
                sortBy: [
                    SortDescriptor(\CatalogEntryRecord.sortNumber),
                    SortDescriptor(\CatalogEntryRecord.nameKey, comparator: .lexical),
                    SortDescriptor(\CatalogEntryRecord.id, comparator: .lexical)
                ]
            )
            descriptor.fetchLimit = ChannelVariantsStore.limit
            found[key] = ((try? context.fetch(descriptor)) ?? []).map(CatalogRow.init)
        }
        return found
    }
}

extension EnvironmentValues {
    @Entry var channelVariants: ChannelVariantsStore = .shared
}
