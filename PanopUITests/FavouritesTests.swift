import XCTest

final class FavouritesTests: PanopUITestCase {
    #if os(tvOS)
        func testALongPressOffersToStarAChannel() {
            waitForChannels()
            focusFirstChannel()
            XCUIRemote.shared.press(.select, forDuration: 1.2)

            // A context menu's items are not buttons on tvOS, so match on the label alone.
            let addItem = app.descendants(matching: .any)["Add to Favourites"].firstMatch
            XCTAssertTrue(addItem.waitForExistence(timeout: 10), "a long press did not open the channel's menu")
            XCUIRemote.shared.press(.select)

            let star = app.descendants(matching: .any)["Favourite"].firstMatch
            XCTAssertTrue(star.waitForExistence(timeout: 10), "no star appeared on the channel")
        }

        /// There is no toolbar on Apple TV, so the filter is a row in the list: reachable, and
        /// it narrows to what was starred.
        func testTheFilterRowShowsOnlyFavourites() {
            waitForChannels()
            focusFirstChannel()
            XCUIRemote.shared.press(.select, forDuration: 1.2)
            XCTAssertTrue(app.descendants(matching: .any)["Add to Favourites"].firstMatch.waitForExistence(timeout: 10))
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.descendants(matching: .any)["Favourite"].firstMatch.waitForExistence(timeout: 10))

            // Back up to the filter row, over to Favourites.
            XCUIRemote.shared.press(.up)
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.select)

            XCTAssertTrue(channel("Arte").waitForNonExistence(timeout: 10), "an unstarred channel is in Favourites")
            XCTAssertTrue(channel("3sat").exists)
        }
    #else
        func testStarringAChannelShowsItInFavourites() {
            waitForChannels()
            channel("3sat").press(forDuration: 1.2)
            let addButton = app.buttons["Add to Favourites"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 10), "a long press did not open the channel's menu")
            addButton.tap()
            XCTAssertTrue(app.images["Favourite"].waitForExistence(timeout: 10), "no star appeared on the channel")

            app.buttons["Show"].tap()
            app.buttons["Favourites"].tap()

            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 10))
            XCTAssertTrue(
                channel("Arte").waitForNonExistence(timeout: 10),
                "a channel that was not starred is in Favourites"
            )
        }

        func testAnEmptyFavouritesListSaysHowToAddOne() {
            waitForChannels()
            app.buttons["Show"].tap()
            app.buttons["Favourites"].tap()

            XCTAssertTrue(app.staticTexts["No favourites yet"].waitForExistence(timeout: 10))
        }
    #endif
}
