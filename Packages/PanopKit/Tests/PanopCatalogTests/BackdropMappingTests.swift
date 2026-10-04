import Foundation
@testable import PanopCatalog
import PanopCore
import PanopXtream
import Testing

@Suite("Backdrop mapping")
struct BackdropMappingTests {
    @Test func `a series keeps the panel's first backdrop`() {
        let series = XtreamSeries(
            seriesID: 1,
            name: "Show",
            backdropURLs: ["", "http://img/b1.jpg", "http://img/b2.jpg"]
        )
        let entry = EntryMapping.entry(from: series, groups: [:])
        #expect(entry.backdropURL == "http://img/b1.jpg")
    }

    @Test func `a series without one has none`() {
        let entry = EntryMapping.entry(from: XtreamSeries(seriesID: 2, name: "Show"), groups: [:])
        #expect(entry.backdropURL == nil)
    }
}
