import PanopCore
import Testing

@Suite("Putting categories in order")
struct CategoryOrderTests {
    let order = ["A", "B", "C", "D", "E"]

    @Test func `one name moves a place and stops at the edge`() {
        #expect(CategoryOrder.moved(order, chosen: ["C"], by: -1) == ["A", "C", "B", "D", "E"])
        #expect(CategoryOrder.moved(order, chosen: ["C"], by: 1) == ["A", "B", "D", "C", "E"])
        #expect(CategoryOrder.moved(order, chosen: ["A"], by: -1) == order)
        #expect(CategoryOrder.moved(order, chosen: ["E"], by: 1) == order)
    }

    @Test func `several names move together, keeping their order among themselves`() {
        #expect(CategoryOrder.moved(order, chosen: ["B", "D"], by: -1) == ["B", "A", "D", "C", "E"])
        #expect(CategoryOrder.moved(order, chosen: ["B", "D"], by: 1) == ["A", "C", "B", "E", "D"])
    }

    @Test func `a block that reaches the edge stops there and does not tear apart`() {
        #expect(CategoryOrder.moved(order, chosen: ["A", "B"], by: -1) == order)
        #expect(CategoryOrder.moved(order, chosen: ["A", "C"], by: -1) == ["A", "C", "B", "D", "E"])
        #expect(CategoryOrder.moved(order, chosen: ["D", "E"], by: 1) == order)
    }

    @Test func `names that are not in the list change nothing`() {
        #expect(CategoryOrder.moved(order, chosen: ["Z"], by: 1) == order)
        #expect(CategoryOrder.moved(order, chosen: [], by: 1) == order)
    }

    @Test func `names go to the top or the bottom, in the order they had`() {
        #expect(CategoryOrder.placed(order, chosen: ["D", "B"], atTop: true) == ["B", "D", "A", "C", "E"])
        #expect(CategoryOrder.placed(order, chosen: ["D", "B"], atTop: false) == ["A", "C", "E", "B", "D"])
    }

    @Test func `the filter finds names by their words, ignoring case and accents`() {
        let names = ["DE | Sport", "UK | Sports", "FR | Cinéma", "Kids", "Sport Extra"]
        #expect(CategoryOrder.matching(names, filter: "sport") == ["DE | Sport", "UK | Sports", "Sport Extra"])
        #expect(CategoryOrder.matching(names, filter: "cinema") == ["FR | Cinéma"])
        #expect(CategoryOrder.matching(names, filter: "de sport") == ["DE | Sport"])
        #expect(CategoryOrder.matching(names, filter: "  ") == names)
        #expect(CategoryOrder.matching(names, filter: "zzz").isEmpty)
    }
}
