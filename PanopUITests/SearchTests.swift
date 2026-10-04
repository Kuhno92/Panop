import XCTest

final class SearchTests: PanopUITestCase {
    #if !os(tvOS)
        private func search(_ text: String) {
            waitForChannels()
            app.tabBars.buttons["Home"].tap()
            app.buttons["Search"].tap()
            let field = app.textFields["searchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field. Screen:\n\(app.debugDescription)")
            field.typeText(text)
            XCTAssertEqual(field.value as? String, text, "the field did not keep what was typed")
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

            XCTAssertTrue(
                app.staticTexts["Movies"].waitForExistence(timeout: 10),
                "no movie results. Screen:\n\(app.debugDescription)"
            )
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alien'")).firstMatch.exists)
        }

        func testAFilmFoundBySearchOpensItsPage() {
            search("Dune")

            let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Dune'")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10), "the film was not found")
            result.tap()

            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10), "the film's page did not open")
        }
    #else
        override var startTab: String {
            "home"
        }

        /// The magnifier is the first thing under the tab bar, and opens a field.
        func testTheMagnifierOpensAField() {
            XCTAssertTrue(
                app.buttons["Search"].waitForExistence(timeout: 30),
                "no search button. Screen:\n\(app.debugDescription)"
            )
            // Focus starts on the tab bar or, once the screen has settled, already in the content: go down until
            // it is on the magnifier, rather than count presses.
            for _ in 0 ..< 3 where !app.buttons["Search"].hasFocus {
                XCUIRemote.shared.press(.down)
            }
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(
                app.textFields["searchField"].waitForExistence(timeout: 10),
                "no search field. Screen:\n\(app.debugDescription)"
            )
        }
    #endif
}
