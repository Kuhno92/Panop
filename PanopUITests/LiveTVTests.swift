import XCTest

final class LiveTVTests: PanopUITestCase {
    func testSeededChannelsAppear() {
        waitForChannels()
        XCTAssertTrue(channel("Arte").exists)
    }

    #if !os(tvOS)
        func testSearchNarrowsTheList() {
            waitForChannels()
            app.buttons["Search"].tap()
            let search = app.textFields["searchField"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), "no search field once a playlist exists")

            search.typeText("zdf")

            XCTAssertTrue(channel("3sat").waitForNonExistence(timeout: 10), "a non-matching channel stayed")
            XCTAssertTrue(channel("ZDF").waitForExistence(timeout: 5))
        }
    #endif

    #if !os(tvOS)
        /// The list follows the provider's order by default, which puts "Das Erste" (the file's first
        /// channel) first. Sorting by name moves it below the screen, behind "3sat" and the rest.
        func testTheListFollowsTheProviderUnlessSortedByName() {
            waitForChannels()
            XCTAssertTrue(channel("Das Erste").exists, "the provider's first channel is not first")

            app.buttons["Sort"].tap()
            app.buttons["By name"].tap()

            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 10))
            XCTAssertTrue(
                channel("Das Erste").waitForNonExistence(timeout: 10),
                "the alphabet should not put it on the first screen"
            )
        }
    #endif

    #if !os(tvOS)
        func testANarrowedCategoryShowsOnlyItsChannels() {
            waitForChannels()
            XCTAssertTrue(app.buttons["Other"].waitForExistence(timeout: 10), "the seeded category is not offered")
            app.buttons["Other"].tap()

            XCTAssertTrue(channel("Channel 10").waitForExistence(timeout: 10), "the category's channels did not show")
            XCTAssertFalse(channel("3sat").exists, "a channel from another category is still listed")
        }
    #endif

    #if !os(tvOS)
        func testARowSaysWhatIsOnNowAndItsGuideListsWhatFollows() {
            waitForChannels()
            XCTAssertTrue(
                app.staticTexts["Now: Seeded News"].waitForExistence(timeout: 15),
                "the row for a channel with a guide does not say what is on"
            )

            channel("3sat").press(forDuration: 1.2)
            XCTAssertTrue(app.buttons["Programme Guide"].waitForExistence(timeout: 10), "no guide in the row's menu")
            app.buttons["Programme Guide"].tap()

            XCTAssertTrue(
                app.staticTexts["Seeded Film"].waitForExistence(timeout: 10),
                "the next programme is not listed"
            )
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Watch'")).firstMatch.exists)
        }
    #endif

    #if !os(tvOS)
        func testACategoryCanBeHiddenAndTheListFollows() {
            waitForChannels()
            app.buttons["Edit categories"].tap()
            XCTAssertTrue(
                app.buttons["Hide Germany"].waitForExistence(timeout: 10),
                "the editor does not offer the seeded category. Screen:\n\(app.debugDescription)"
            )
            app.buttons["Hide Germany"].tap()
            app.buttons["Done"].tap()

            XCTAssertTrue(
                channel("3sat").waitForNonExistence(timeout: 10),
                "a channel of a hidden category is still listed"
            )
            XCTAssertFalse(app.buttons["Germany"].exists, "the hidden category is still a chip")

            // And back: the editor still lists it, and showing it returns its channels.
            app.buttons["Edit categories"].tap()
            app.buttons["Show Germany"].tap()
            app.buttons["Done"].tap()
            XCTAssertTrue(
                channel("3sat").waitForExistence(timeout: 10),
                "a category shown again did not bring its channels"
            )
        }

        func testACategoryCanBeMovedEarlier() {
            waitForChannels()
            app.buttons["Edit categories"].tap()
            XCTAssertTrue(app.buttons["Move Other up"].waitForExistence(timeout: 10))
            app.buttons["Move Other up"].tap()

            // Other is now first, so its own "up" is gone and Germany's "down" is the one that is not.
            XCTAssertFalse(app.buttons["Move Other up"].isEnabled, "Other did not become first")
            app.buttons["Done"].tap()
        }
    #endif
}
