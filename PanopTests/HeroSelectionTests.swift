import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import PanopDiscover
import Testing

@Suite("Hero selection")
struct HeroSelectionTests {
    private func row(_ id: String, hasPoster: Bool = true) -> CatalogRow {
        CatalogRow(CatalogEntryRecord(
            playlist: "p",
            entry: CatalogEntry(id: id, kind: .movie, name: id, iconURL: hasPoster ? "http://img/\(id).jpg" : nil)
        ))
    }

    private func rail(_ id: String, _ rows: [CatalogRow]) -> Rail {
        Rail(kind: .curated(.movie, id), keys: rows.map(\.id), subject: nil)
    }

    private func index(_ rows: [CatalogRow]) -> [String: CatalogRow] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    @Test
    func `one title from each rail, in the rails' order, those with wide artwork first`() {
        let (first, second, third, fourth, fifth) = (row("a1"), row("a2"), row("b1"), row("c1"), row("d1"))
        let rails = [rail("a", [first, second]), rail("b", [third]), rail("c", [fourth]), rail("d", [fifth])]
        let wide: Set<String> = [second.id, third.id, fourth.id]

        let chosen = HeroSelection
            .rows(rails: rails, rows: index([first, second, third, fourth, fifth])) { wide.contains($0.id) ? "w" : nil }

        #expect(chosen.map(\.entryID) == ["a2", "b1", "c1"], "a1 has none, so the rail gives a2; d has none at all")
    }

    @Test
    func `a title is shown once however many rails hold it`() {
        let shared = row("s")
        let chosen = HeroSelection.rows(
            rails: [rail("a", [shared]), rail("b", [shared, row("t")])],
            rows: index([shared, row("t")])
        ) { _ in "w" }

        #expect(chosen.map(\.entryID) == ["s", "t"])
    }

    @Test
    func `too few with wide artwork are topped up with posters, never beyond the limit`() {
        let rows = (1 ... 9).map { row("r\($0)") }
        let rails = rows.map { rail($0.entryID, [$0]) }

        let fewWide = HeroSelection.rows(rails: rails, rows: index(rows)) { $0.entryID == "r4" ? "w" : nil }
        #expect(fewWide.count == 3)
        #expect(fewWide.first?.entryID == "r4")

        let allWide = HeroSelection.rows(rails: rails, rows: index(rows)) { _ in "w" }
        #expect(allWide.count == HeroSelection.limit)
    }

    @Test
    func `a title without a poster is never featured`() {
        let bare = row("x", hasPoster: false)
        #expect(HeroSelection.rows(rails: [rail("a", [bare])], rows: index([bare])) { _ in "w" }.isEmpty)
    }
}
