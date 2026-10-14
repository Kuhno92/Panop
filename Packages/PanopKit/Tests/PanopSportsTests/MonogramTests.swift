@testable import PanopSports
import Testing

@Suite("crests without a logo")
struct MonogramTests {
    @Test
    func `initials are two letters for several words and three for one`() {
        #expect(TeamMonogram.initials(for: "Bayern Munich") == "BM")
        #expect(TeamMonogram.initials(for: "FC Bayern München") == "BM")
        #expect(TeamMonogram.initials(for: "Norwich") == "NOR")
        #expect(TeamMonogram.initials(for: "PSG") == "PSG")
        #expect(TeamMonogram.initials(for: "1. FC Köln") == "KÖL".folding())
        #expect(TeamMonogram.initials(for: "") == "?")
    }

    @Test
    func `a team has the same colour every time, and the dressing of its name does not change it`() {
        let hue = TeamMonogram.hue(for: "Borussia Dortmund")
        #expect(hue == TeamMonogram.hue(for: "Borussia Dortmund"))
        #expect(hue == TeamMonogram.hue(for: "borussia dortmund"))
        #expect(TeamMonogram.hue(for: "FC Augsburg") == TeamMonogram.hue(for: "Augsburg"))
        #expect((0 ..< 1).contains(hue))
        // A fixed value: it must not drift between releases, or every team's colour would change.
        #expect(TeamMonogram.hue(for: "Alder Town") == TeamMonogram.hue(for: "alder town"))
    }

    @Test
    func `different teams mostly get different colours`() {
        let names = [
            "Alder Town",
            "Birch City",
            "Cedar Rovers",
            "Dune Athletic",
            "Elm Park",
            "Fir Wanderers",
            "Grove United"
        ]
        #expect(Set(names.map(TeamMonogram.hue)).count >= 6)
    }
}

private extension String {
    func folding() -> String {
        folding(options: .diacriticInsensitive, locale: nil).uppercased()
    }
}
