import XCTest

final class SearchTests: PanopUITestCase {
    #if !os(tvOS)
        /// The tab bar's magnifier opens the search field of the screen on show.
        private func search(_ text: String, on tab: String = "Home") {
            waitForChannels()
            app.tabBars.buttons[tab].tap()
            XCTAssertFalse(
                app.textFields["searchField"].exists,
                "the search field was open before the magnifier was chosen"
            )
            app.tabBars.buttons["Search"].tap()
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

        /// On the Series screen the search is of series: the tab bar's magnifier does not leave for a screen of its
        /// own.
        func testSearchOnSeriesSearchesSeries() {
            search("Sev", on: "Series")

            XCTAssertTrue(app.buttons["Severance"].waitForExistence(timeout: 10), "the show was not found")
            XCTAssertFalse(app.buttons["Dark"].exists, "a show that does not match stayed")
            XCTAssertFalse(app.staticTexts["Channels"].exists, "the search left Series for the all-round one")
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

        /// The magnifier is the last icon of the tab bar, and it opens the Search screen, which has the field. The
        /// other
        /// screens have none of their own: it filled the top of each, with its keyboard above the content.
        func testTheTabBarOffersSearch() {
            XCTAssertTrue(app.tabBars.buttons["Search"].waitForExistence(timeout: 30), "no Search in the tab bar")
            XCTAssertFalse(app.searchFields.firstMatch.exists, "Home shows a search field of its own")

            // Focus is on the tab bar, at Home: the magnifier is five icons to the right.
            for _ in 0 ..< 5 {
                XCUIRemote.shared.press(.right)
            }
            XCUIRemote.shared.press(.select)

            XCTAssertTrue(
                app.searchFields.firstMatch.waitForExistence(timeout: 10),
                "no search field on the Search screen. Screen:\n\(app.debugDescription)"
            )
        }
    #endif
}
