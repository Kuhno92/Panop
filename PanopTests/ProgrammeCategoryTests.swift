@testable import Panop
import Testing

@Suite("Programme categories")
struct ProgrammeCategoryTests {
    @Test(arguments: [
        (["News"], ProgrammeCategory.news), (["Nachrichten"], .news), (["Weather"], .news),
        (["Sports"], .sport), (["Sport", "Fußball"], .sport), (["Football"], .sport),
        (["Spielfilm"], .film), (["Movie / Drama"], .film), (["Fernsehfilm"], .film),
        (["Serie"], .series), (["Krimiserie"], .series), (["Soap"], .series), (["Drama"], .series),
        (["Kinder"], .kids), (["Children's"], .kids), (["Animation"], .kids), (["Kids", "Movie"], .kids),
        (["Dokumentation"], .documentary), (["Doku / Wissen"], .documentary), (["Reportage"], .documentary),
        (["Music"], .music), (["Konzert"], .music), (["Oper"], .music),
        (["Talk-Show"], .entertainment), (["Comedy"], .entertainment), (["Quiz"], .entertainment),
        (["Something else"], .other), ([], .other)
    ] as [([String], ProgrammeCategory)])
    func `the guide's own words say what kind of programme it is`(
        _ categories: [String],
        _ expected: ProgrammeCategory
    ) {
        #expect(ProgrammeCategory.classify(categories: categories) == expected)
    }

    @Test
    func `the more specific kind wins when a programme is several`() {
        #expect(ProgrammeCategory.classify(categories: ["Sport", "Documentary"]) == .sport)
        #expect(ProgrammeCategory.classify(categories: ["Kids", "Series"]) == .kids)
    }

    @Test
    func `a title only decides for a bulletin or a big competition`() {
        #expect(ProgrammeCategory.classify(categories: [], title: "Tagesschau") == .news)
        #expect(ProgrammeCategory.classify(categories: [], title: "Bundesliga: Dortmund - Bayern") == .sport)
        #expect(ProgrammeCategory.classify(categories: [], title: "Game of Thrones") == .other)
        #expect(ProgrammeCategory.classify(categories: [], title: "The Show Must Go On") == .other)
    }

    @Test
    func `the guide's categories win over the title`() {
        #expect(ProgrammeCategory.classify(categories: ["Documentary"], title: "Tagesschau") == .documentary)
    }

    @Test
    func `every kind has a place in the list for a colour key`() {
        #expect(ProgrammeCategory.allCases.count == 9)
        #expect(Set(ProgrammeCategory.allCases.map(\.rawValue)).count == 9)
    }
}
