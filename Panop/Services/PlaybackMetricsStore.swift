import Foundation
import PanopPlayback

/// The last few hundred viewing sessions, on this device only.
///
/// A JSON file in Application Support, written when a session ends and at no other time: a
/// write during playback would hitch the picture it is measuring. Off the main thread, in an
/// actor, so ending a session never waits on the disk. It never leaves the device and holds no
/// address, name or account (`PlaybackSessionRecord` has none to hold).
actor PlaybackMetricsStore {
    /// How many sessions are kept; the oldest go first.
    static let capacity = 300

    private let file: URL
    private var records: [PlaybackSessionRecord]

    init(file: URL = PlaybackMetricsStore.defaultFile) {
        self.file = file
        let data = try? Data(contentsOf: file)
        records = data.flatMap { try? JSONDecoder().decode([PlaybackSessionRecord].self, from: $0) } ?? []
    }

    nonisolated static var defaultFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PlaybackSessions.json")
    }

    func append(_ record: PlaybackSessionRecord) {
        records.append(record)
        if records.count > Self.capacity {
            records.removeFirst(records.count - Self.capacity)
        }
        save()
    }

    func all() -> [PlaybackSessionRecord] {
        records
    }

    func statistics() -> PlaybackStatistics {
        PlaybackStatistics(records)
    }

    func clear() {
        records = []
        try? FileManager.default.removeItem(at: file)
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
