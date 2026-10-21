import Foundation
import Observation
import SwiftData

/// The configuration record in the cloud container, read through explicit fetches (ADR 0003).
@MainActor
@Observable
final class VPNSyncStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    var record: (blob: Data?, removed: Bool) {
        guard let found = records().first else { return (nil, false) }
        return (found.encryptedConfig, found.removed)
    }

    func setBlob(_ blob: Data?, removed: Bool = false) {
        let found = records()
        let record = found.first ?? VPNConfigRecord()
        if found.isEmpty {
            context.insert(record)
        }
        record.encryptedConfig = blob
        record.removed = removed
        record.updatedAt = .now
        try? context.save()
    }

    private func records() -> [VPNConfigRecord] {
        let found = (try? context.fetch(FetchDescriptor<VPNConfigRecord>(sortBy: [SortDescriptor(
            \.updatedAt,
            order: .reverse
        )]))) ?? []
        // Two devices may each have made one before the first arrived: the newest stands.
        if found.count > 1 {
            for extra in found.dropFirst() {
                context.delete(extra)
            }
            try? context.save()
        }
        return Array(found.prefix(1))
    }
}
