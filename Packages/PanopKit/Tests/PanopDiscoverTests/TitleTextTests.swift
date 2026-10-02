@testable import PanopDiscover
import Testing

@Suite("Title text")
struct TitleTextTests {
    @Test(arguments: [
        ("DE - Backrooms (2026)", "Backrooms"),
        ("DE-[4K] - Lioness (2023) (US)", "Lioness"),
        ("Widow's Bay (2026) (US)", "Widow's Bay"),
        ("Heat", "Heat"),
        ("  Heat  (1995)  ", "Heat"),
        ("Spider-Man - Homecoming", "Spider-Man - Homecoming"),
        ("EN - The Office", "The Office"),
        ("(2020)", "")
    ])
    func `provider decoration is removed`(name: String, cleaned: String) {
        #expect(TitleText.clean(name) == cleaned)
    }

    @Test(arguments: [
        ("Toy Story 5 (2026)", "toy story"),
        ("Toy Story", "toy story"),
        ("DE - Toy Story 2 (1999)", "toy story"),
        ("Spider-Man: Brand New Day", "spider-man"),
        ("Rocky IV", "rocky"),
        ("Fast & Furious 7", "fast & furious"),
        ("Alien: Romulus (2024)", "alien")
    ])
    func `a film series shares its stem`(name: String, stem: String) {
        #expect(TitleText.stem(of: name) == stem)
    }

    @Test(arguments: ["Up", "It", "2012", "", "V (2009)"])
    func `a short or empty title has no stem to share`(name: String) {
        #expect(TitleText.stem(of: name) == nil)
    }

    @Test
    func `the same title in two versions is recognised, and a different year is not the same`() {
        #expect(TitleText.sameTitleKey(name: "DE - Heat (1995)", year: 1995) == TitleText.sameTitleKey(
            name: "Heat",
            year: 1995
        ))
        #expect(TitleText.sameTitleKey(name: "Heat", year: 1995) != TitleText.sameTitleKey(name: "Heat", year: 2024))
    }

    @Test
    func `genres are split on slashes and commas, lower-cased, and keep their ampersands`() {
        #expect(TitleText.genres(from: "Krimi / Drama") == ["krimi", "drama"])
        #expect(TitleText.genres(from: "Sci-Fi & Fantasy, Action & Adventure") == [
            "sci-fi & fantasy",
            "action & adventure"
        ])
        #expect(TitleText.genres(from: nil).isEmpty)
        #expect(TitleText.genres(from: " / , ").isEmpty)
    }

    @Test
    func `only the leading cast is kept`() {
        let names = (1 ... 20).map { "Actor \($0)" }.joined(separator: ", ")

        #expect(TitleText.people(from: names).count == 8)
        #expect(TitleText.people(from: "Alan Ritchson, Willa Fitzgerald") == ["alan ritchson", "willa fitzgerald"])
    }
}
