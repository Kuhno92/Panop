import CryptoKit
import Foundation

/// Original image bytes on disk, bounded in size, oldest-used evicted first.
///
/// The bytes are kept as downloaded and downsampled when loaded, so a different size later
/// needs no second download. Lives in Caches, where the system may clear it, and nothing
/// here may depend on it being there.
actor DiskImageCache {
    private struct Stored {
        let url: URL
        let size: Int
        let used: Date
    }

    private let directory: URL
    private let maxBytes: Int
    private var writesSinceTrim = 0

    /// How many writes between checks of the total size. Walking the directory on every
    /// write would make a fast scroll pay for it.
    private let trimEvery = 40

    init(directory: URL, maxBytes: Int) {
        self.directory = directory
        self.maxBytes = maxBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func data(forKey key: String) -> Data? {
        let file = directory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Reading counts as use, so what is on screen is the last thing to go.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    func store(_ data: Data, forKey key: String) {
        try? data.write(to: directory.appendingPathComponent(key), options: .atomic)
        writesSinceTrim += 1
        if writesSinceTrim >= trimEvery {
            trim()
        }
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(key))
    }

    /// Deletes the least recently used files until the total is within the limit.
    func trim() {
        writesSinceTrim = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        ) else { return }
        var entries: [Stored] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { return nil }
            return Stored(url: url, size: size, used: values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        entries.sort { $0.used < $1.used }
        for entry in entries where total > maxBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    func totalBytes() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
