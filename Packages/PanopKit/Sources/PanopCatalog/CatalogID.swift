import Foundation

/// Stable identifiers and cheap hashes.
///
/// Uses FNV-1a 64. It is not cryptographic and does not need to be: it names
/// rows and detects changed files. It is deterministic across launches and
/// platforms, unlike `Hasher`, whose seed changes per process; that matters
/// because ids are persisted.
public enum CatalogID {
    private static let offset: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    public static func hash64(_ text: String) -> UInt64 {
        var hash = offset
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* prime
        }
        return hash
    }

    /// M3U entries have no provider id, so identity comes from the stream URL.
    /// Grouping is deliberately left out: a provider that reshuffles its
    /// categories must not orphan every favourite.
    public static func m3u(url: String) -> String {
        "m3u:" + hex(hash64(url))
    }

    public static func xtream(_ kind: String, _ remoteID: Int) -> String {
        "\(kind):\(remoteID)"
    }

    static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}

extension ProgrammeKey {
    /// Hash for the importer's seen-set. A full guide is hundreds of thousands
    /// of rows, so the set holds these instead of the keys.
    ///
    /// A collision makes a stale row look current, so it is kept. It can never
    /// make a current row look stale, which is the safe direction to be wrong.
    var hash64: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in channelKey.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        var seconds = Int64(start.timeIntervalSince1970)
        for _ in 0 ..< 8 {
            hash = (hash ^ UInt64(seconds & 0xFF)) &* 0x0000_0100_0000_01B3
            seconds >>= 8
        }
        return hash
    }
}

/// Streaming change detector for a downloaded file.
struct ContentDigest {
    private var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    private var length = 0

    mutating func update(_ data: Data) {
        var value = hash
        for byte in data {
            value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        hash = value
        length += data.count
    }

    /// Length is included so two files that collide on the hash still differ.
    var hex: String {
        CatalogID.hex(hash) + "-" + String(length, radix: 16)
    }
}
