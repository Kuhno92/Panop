import Foundation

/// Putting categories in the order a person wants, one at a time or many at once. Pure: it takes the order as it is and
/// the names the person chose, and gives the order that follows.
public enum CategoryOrder {
    /// The chosen names each one place earlier (`-1`) or later (`1`), the rest keeping their order. A chosen name next
    /// to
    /// another chosen one moves with it, and one at the edge stays where it is, so a run of chosen names moves as a
    /// block until its first or last reaches the edge.
    public static func moved(_ order: [String], chosen: Set<String>, by step: Int) -> [String] {
        guard step != 0, !chosen.isEmpty else { return order }
        var result = order
        let indices = step < 0 ? Array(result.indices) : Array(result.indices.reversed())
        for index in indices where chosen.contains(result[index]) {
            let target = index + (step < 0 ? -1 : 1)
            guard result.indices.contains(target), !chosen.contains(result[target]) else { continue }
            result.swapAt(index, target)
        }
        return result
    }

    /// The chosen names first (or last), in the order they already had, then the rest in theirs.
    public static func placed(_ order: [String], chosen: Set<String>, atTop: Bool) -> [String] {
        let picked = order.filter { chosen.contains($0) }
        let others = order.filter { !chosen.contains($0) }
        return atTop ? picked + others : others + picked
    }

    /// The names whose words contain what was typed: case and accents ignored, and every typed word must be found.
    public static func matching(_ names: [String], filter: String) -> [String] {
        let words = filter.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !words.isEmpty else { return names }
        return names.filter { name in
            let folded = fold(name)
            return words.allSatisfy { folded.contains($0) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
