import XCTest

final class SearchTests: PanopUITestCase {
    #if !os(tvOS)
        private func search(_ text: String) {
            waitForChannels()
            app.tabBars.buttons["Home"].tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field. Screen:\n\(app.debugDescription)")
            field.tap()
            field.typeText(text)
        }

        /// The list is lazy, so a query is specific enough for each section to be on screen.
        func testASearchFindsAChannel() {
            search("3sat")

            XCTAssertTrue(app.staticTexts["Channels"].waitForExistence(timeout: 10), "no channel results")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '3sat'")).firstMatch.exists)
            XCTAssertFalse(app.staticTexts["Movies"].exists, "a section with no match was drawn")
        }

        func testASearchFindsAFilm() {
            search("Alien")

            XCTAssertTrue(app.staticTexts["Movies"].waitForExistence(timeout: 10), "no movie results")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alien'")).firstMatch.exists)
        }

        func testAFilmFoundBySearchOpensItsPage() {
            search("Dune")

            let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Dune'")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10), "the film was not found")
            result.tap()

            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10), "the film's page did not open")
        }
    #endif
}
