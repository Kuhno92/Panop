import Foundation
import PanopCore
import SwiftData

/// Marks, in a catalog that was imported before the guide leads were recorded, which live channel of each guide is the
/// one
/// a grouped list shows.
///
/// An import marks them as it goes, but a playlist that has not changed is not imported again (its digest is the
/// same), so a catalog from before would never get its marks and the list would show every version. This does what the
/// import does, from what is already stored: the first channel of each guide key in the provider's order, overall and
/// within its category. Once, in the background, a page of channels at a time.
nonisolated enum GuideLeadBackfill {
    static let doneKey = "guideLeadsMarked"
    /// Channels read and written at a time, so memory stays flat on an 80,000-channel playlist.
    static let pageSize = 2000

    /// Runs once for this device. A playlist added later is marked as it is imported.
    static func runOnce(container: ModelContainer, playlists: [String], defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: doneKey) else { return }
        for playlist in playlists {
            guard !Task.isCancelled else { return }
            await mark(playlist: playlist, in: container)
        }
        // With no playlist yet there was nothing to mark: the first one is marked as it is imported, and this runs
        // once more over it, harmlessly.
        if !playlists.isEmpty {
            defaults.set(true, forKey: doneKey)
        }
    }

    /// One playlist's live channels with a guide key, in the provider's order. Returns how many were changed.
    @discardableResult
    static func mark(playlist: String, in container: ModelContainer) async -> Int {
        await Task.detached(priority: .utility) {
            var guideKeys = Set<String>()
            var categoryKeys = Set<String>()
            var changed = 0
            var offset = 0
            let live = MediaKind.live.rawValue
            while true {
                // A context for each page: the records of the last one are not kept.
                let context = ModelContext(container)
                context.autosaveEnabled = false
                var descriptor = FetchDescriptor<CatalogEntryRecord>(
                    predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == live && $0.epgKey != nil },
                    sortBy: [
                        SortDescriptor(\CatalogEntryRecord.sortNumber),
                        SortDescriptor(\CatalogEntryRecord.nameKey, comparator: .lexical),
                        SortDescriptor(\CatalogEntryRecord.id, comparator: .lexical)
                    ]
                )
                descriptor.fetchLimit = pageSize
                descriptor.fetchOffset = offset
                guard let page = try? context.fetch(descriptor), !page.isEmpty else { break }
                for record in page {
                    guard let key = record.epgKey, !key.isEmpty else { continue }
                    let guide = guideKeys.insert(key).inserted
                    let category = categoryKeys.insert("\(record.groupName ?? "")\u{1F}\(key)").inserted
                    if record.isGuideLead != guide {
                        record.isGuideLead = guide
                        changed += 1
                    }
                    if record.isCategoryLead != category {
                        record.isCategoryLead = category
                        changed += 1
                    }
                }
                try? context.save()
                offset += page.count
                if page.count < pageSize {
                    break
                }
            }
            return changed
        }.value
    }
}
