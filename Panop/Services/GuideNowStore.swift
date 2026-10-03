import Foundation
import Observation
import SwiftData
import SwiftUI

/// What is on now, for the channels a list is showing, read in the background and kept ready.
///
/// A row never reads the guide itself. It asks here, which answers from memory at once: either
/// with the programme, or with nothing, in which case the line stays blank until the answer
/// arrives. Rows that scroll past too fast to be read are never looked up, and the lookups that
/// are wanted go in one read on a background thread, not one on the main thread per row.
@MainActor
@Observable
final class GuideNowStore {
    /// What a channel has on, and until when. `nil` is "looked up, nothing on".
    private struct Entry {
        var programme: ProgrammeSnapshot?
        /// What starts when `programme` ends, or the first to start when nothing is on.
        var next: ProgrammeSnapshot?
        var validUntil: Date
    }

    /// Wait before reading, so a row that is only passing is gone by then, and its request with it.
    static let settleDelay = Duration.milliseconds(120)
    /// A channel with nothing on is looked at again after this: a guide may have just arrived.
    static let recheckAfter: TimeInterval = 30
    /// Shared by every list, so a channel is read once however many rows ask.
    static let shared = GuideNowStore()

    private var entries: [String: Entry] = [:]
    @ObservationIgnored private var wanted: Set<GuideKey> = []
    @ObservationIgnored private var inFlight: Set<GuideKey> = []
    @ObservationIgnored private var batch: Task<Void, Never>?
    @ObservationIgnored private var reader: GuideReader?
    @ObservationIgnored private var generation = 0

    /// The programme on now, if it is known. Reads memory only.
    func current(playlist: String, epgKey: String?, now: Date = .now) -> ProgrammeSnapshot? {
        guard let epgKey, let entry = entries[Self.id(playlist, epgKey)], entry.validUntil > now else { return nil }
        return entry.programme.flatMap { $0.isOn(at: now) ? $0 : nil }
    }

    /// The programme after the one on now, if it is known. Reads memory only.
    func next(playlist: String, epgKey: String?, now: Date = .now) -> ProgrammeSnapshot? {
        guard let epgKey, let entry = entries[Self.id(playlist, epgKey)], entry.validUntil > now else { return nil }
        return entry.next.flatMap { $0.start >= now || entry.programme?.isOn(at: now) == true ? $0 : nil }
    }

    /// Whether to ask: nothing known, or what was known has run out.
    func needs(playlist: String, epgKey: String?, now: Date = .now) -> Bool {
        guard let epgKey, !epgKey.isEmpty else { return false }
        guard let entry = entries[Self.id(playlist, epgKey)] else { return true }
        return entry.validUntil <= now
    }

    /// Asks for a channel's programme. Cheap, and folded with the others asked for at about the
    /// same moment into one background read.
    func request(playlist: String, epgKey: String?, in container: ModelContainer) {
        guard let epgKey, !epgKey.isEmpty, needs(playlist: playlist, epgKey: epgKey) else { return }
        let key = GuideKey(playlist: playlist, epgKey: epgKey)
        guard !inFlight.contains(key) else { return }
        wanted.insert(key)
        if reader == nil {
            reader = GuideReader(container: container)
        }
        guard batch == nil, let reader else { return }
        let current = generation
        batch = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            let keys = wanted
            wanted = []
            inFlight.formUnion(keys)
            let found = await reader.now(keys)
            guard current == generation else { return }
            // One assignment for the lot, so a screenful of rows is one update, not twenty.
            var updated = entries
            let moment = Date.now
            for (key, answer) in found {
                // Good until what is on ends. With nothing on, until what is next begins, or a look
                // again soon in case a guide has just arrived.
                let soon = moment.addingTimeInterval(Self.recheckAfter)
                let until = answer.now?.stop ?? answer.next.map { min($0.start, soon) } ?? soon
                updated[Self.id(key.playlist, key.epgKey)] = Entry(
                    programme: answer.now, next: answer.next, validUntil: until
                )
            }
            entries = updated
            inFlight.subtract(keys)
            batch = nil
            // Anything asked for while this was reading goes in the next.
            if !wanted.isEmpty, let any = wanted.first {
                request(playlist: any.playlist, epgKey: any.epgKey, in: container)
            }
        }
    }

    /// A row that scrolled away before its answer was wanted: it need not be read.
    func withdraw(playlist: String, epgKey: String?) {
        guard let epgKey else { return }
        wanted.remove(GuideKey(playlist: playlist, epgKey: epgKey))
    }

    /// Forgets everything, for when the guide has been replaced.
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

nonisolated struct GuideKey: Hashable, Sendable {
    var playlist: String
    var epgKey: String
}

/// What a channel has on, and what follows.
nonisolated struct GuideAnswer: Sendable {
    var now: ProgrammeSnapshot?
    var next: ProgrammeSnapshot?
}

/// Reads the guide off the main thread, on a context of its own.
actor GuideReader {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// What is on now for each channel asked about, in one pass over one context.
    func now(_ keys: Set<GuideKey>) -> [GuideKey: GuideAnswer] {
        let context = ModelContext(container)
        let moment = Date.now
        var found: [GuideKey: GuideAnswer] = [:]
        for key in keys {
            let both = GuideLookup.nowAndNext(playlist: key.playlist, epgKey: key.epgKey, at: moment, in: context)
            found[key] = GuideAnswer(now: both.now, next: both.next)
        }
        return found
    }
}

extension EnvironmentValues {
    @Entry var guideNow: GuideNowStore = .shared
}
