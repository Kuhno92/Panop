import Foundation

/// What was fetched from the service, kept as it came, so a screen can draw at once and the next launch needs no
/// request for what is still fresh. The budget is small, so this is what keeps it from being spent on drawing.
///
/// One file per call (`fixtures-2026-10-14`, `standings-53`), written whole and atomically. A failed write or read
/// loses that entry and nothing else.
actor SportsCacheStore {
    struct Entry: Sendable {
        var data: Data
        var fetchedAt: Date
    }

    private let directory: URL
    private let now: @Sendable () -> Date

    init(directory: URL = SportsCacheStore.defaultDirectory, now: @escaping @Sendable () -> Date = { .now }) {
        self.directory = directory
        self.now = now
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Panop/Sports", isDirectory: true)
    }

    func read(_ name: String) -> Entry? {
        let url = file(name)
        guard let data = try? Data(contentsOf: url),
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return nil }
        return Entry(data: data, fetchedAt: date)
    }

    func write(_ name: String, data: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = file(name)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
    }

    /// Everything, such as when the key is taken out: what was fetched with it goes with it.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Entries not written for `age` seconds are removed, so yesterday's matches do not pile up.
    func prune(olderThan age: TimeInterval) {
        let cutoff = now().addingTimeInterval(-age)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for url in urls {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date, date < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func file(_ name: String) -> URL {
        // Names are made here, from numbers and dates; still, nothing that could leave the directory.
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }
}
