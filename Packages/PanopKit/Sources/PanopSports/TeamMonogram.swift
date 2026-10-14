import Foundation

/// A crest for a team that has no logo, or whose logo has not arrived: its initials, on a colour that is the team's own
/// in every launch and on every device.
public enum TeamMonogram {
    /// "Bayern Munich" is "BM", "Norwich" is "NOR", "PSG" stays "PSG": two letters for a name of several words, three
    /// for one word.
    public static func initials(for name: String) -> String {
        let words = TeamNames.core(name)
        guard let first = words.first else { return "?" }
        if words.count >= 2 {
            return (String(first.prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
        return String(first.prefix(3)).uppercased()
    }

    /// 0 to 1, from the name alone. Not `hashValue`, which differs from one launch to the next.
    public static func hue(for name: String) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in TeamNames.core(name).joined(separator: " ").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Double(hash % 360) / 360
    }
}
