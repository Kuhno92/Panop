import Foundation
import Observation
import SwiftData

/// The programmes of the channels a guide grid shows, over the stretch of time it draws.
///
/// Like `GuideNowStore`, a row never reads the guide: it asks here, which answers from memory, and the rows
/// that are wanted at about the same moment go in one read on a background thread. A row that scrolls past
/// too fast to matter is withdrawn before it is read.
@MainActor
@Observable
final class GuideGridModel {
    /// What a channel has over the window. `[]` is "looked up, nothing there".
    private(set) var programmes: [GuideKey: [ProgrammeSnapshot]] = [:]

    static let settleDelay = Duration.milliseconds(100)
    /// More than a channel shows in half a day, so the cut is never seen.
    static let perChannel = 120

    @ObservationIgnored private var wanted: Set<GuideKey> = []
    @ObservationIgnored private var batch: Task<Void, Never>?
    @ObservationIgnored private var reader: GuideGridReader?
    @ObservationIgnored private var window: ClosedRange<Date>?
    @ObservationIgnored private var generation = 0

    /// Whether the channel has been looked up, with or without a result.
    func isLoaded(_ key: GuideKey) -> Bool {
        programmes[key] != nil
    }

    /// Starts over for a new stretch of time (or after the guide was replaced).
    func reset(window: ClosedRange<Date>) {
        generation += 1
        self.window = window
        programmes = [:]
        wanted = []
        batch?.cancel()
        batch = nil
    }

    /// Asks for a channel's programmes. Cheap, and folded with the others asked for at about the same moment.
    func request(_ key: GuideKey, in container: ModelContainer) {
        guard programmes[key] == nil, let window else { return }
        wanted.insert(key)
        if reader == nil {
            reader = GuideGridReader(container: container)
        }
        guard batch == nil, let reader else { return }
        let current = generation
        batch = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            let keys = wanted
            wanted = []
            let found = await reader.programmes(for: keys, in: window, limit: Self.perChannel)
            batch = nil
            guard current == generation else { return }
            // One assignment for the lot, so a screenful of rows is one update, not twenty.
            var updated = programmes
            for (key, list) in found {
                updated[key] = list
            }
            programmes = updated
            if let again = wanted.first {
                request(again, in: container)
            }
        }
    }

    /// A row that scrolled away before it was read need not be.
    func withdraw(_ key: GuideKey) {
        wanted.remove(key)
    }
}

/// Reads the guide for many channels in one pass, off the main thread, on a context of its own.
actor GuideGridReader {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func programmes(
        for keys: Set<GuideKey>,
        in window: ClosedRange<Date>,
        limit: Int
    ) -> [GuideKey: [ProgrammeSnapshot]] {
        let context = ModelContext(container)
        var found: [GuideKey: [ProgrammeSnapshot]] = [:]
        for key in keys {
            found[key] = GuideLookup.programmes(
                playlist: key.playlist, epgKey: key.epgKey, in: window, limit: limit, context: context
            )
        }
        return found
    }
}
