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
}
