import XCTest

final class LiveTVTests: PanopUITestCase {
    func testSeededChannelsAppear() {
        waitForChannels()
        XCTAssertTrue(channel("Arte").exists)
    }

    #if !os(tvOS)
        func testSearchNarrowsTheList() {
            waitForChannels()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10), "no search field once a playlist exists")

            search.tap()
            search.typeText("zdf")

            XCTAssertTrue(channel("3sat").waitForNonExistence(timeout: 10), "a non-matching channel stayed")
            XCTAssertTrue(channel("ZDF").waitForExistence(timeout: 5))
        }
    #endif

    #if !os(tvOS)
        /// The list is alphabetical by default, which puts "3sat" first and keeps "Das Erste"
        /// (the file's first channel) below the screen. The provider's order reverses that.
        func testProviderOrderPutsTheFilesFirstChannelFirst() {
            waitForChannels()
            XCTAssertFalse(channel("Das Erste").exists, "the alphabet should not put it on the first screen")

            app.buttons["Sort"].tap()
            app.buttons["Provider's order"].tap()

            XCTAssertTrue(
                channel("Das Erste").waitForExistence(timeout: 10),
                "the provider's first channel is not first"
            )
        }
    #endif

    #if !os(tvOS)
        func testANarrowedCategoryShowsOnlyItsChannels() {
            waitForChannels()
            app.buttons["Category"].tap()
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
}
