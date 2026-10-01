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
}
