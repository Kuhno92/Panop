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

            // Back up past the category chips and the Sort row to the filter row, over to Favourites.
            XCUIRemote.shared.press(.up)
            XCUIRemote.shared.press(.up)
            XCUIRemote.shared.press(.up)
            // Focus enters the row near where it came from, so go to the first segment first,
            // then one over: that is Favourites, wherever it started.
            for _ in 0 ..< 3 {
                XCUIRemote.shared.press(.left)
            }
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.select)

            // The first channel in the provider's order is the one that was starred.
            XCTAssertTrue(channel("ZDF").waitForNonExistence(timeout: 10), "an unstarred channel is in Favourites")
            XCTAssertTrue(channel("Das Erste").exists)
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

    #if !os(tvOS)
        func testAHiddenChannelLeavesTheListAndComesBackFromSettings() {
            waitForChannels()
            channel("3sat").press(forDuration: 1.2)
            XCTAssertTrue(app.buttons["Hide Channel"].waitForExistence(timeout: 10), "no Hide in the row's menu")
            app.buttons["Hide Channel"].tap()
            XCTAssertTrue(channel("3sat").waitForNonExistence(timeout: 10), "a hidden channel is still listed")

            app.tabBars.buttons["Settings"].tap()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hidden'")).firstMatch.tap()
            XCTAssertTrue(
                app.staticTexts["3sat"].waitForExistence(timeout: 10),
                "the hidden channel is not listed in Settings"
            )
            app.buttons["Show"].tap()

            app.tabBars.buttons["Live TV"].tap()
            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 10), "a channel shown again is not back")
        }
    #endif
}
