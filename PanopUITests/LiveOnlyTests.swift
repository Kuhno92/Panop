import XCTest

/// A source added for live TV only has no films to show, so the screens for them are not offered.
final class LiveOnlySourceTabsTests: PanopUITestCase {
    override var liveOnly: Bool {
        true
    }

    func testMoviesAndSeriesAreNotOffered() {
        waitForChannels()
        XCTAssertTrue(app.tabBars.buttons["Live TV"].exists)
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertFalse(app.tabBars.buttons["Movies"].exists, "Movies was offered for a live-only source")
        XCTAssertFalse(app.tabBars.buttons["Series"].exists, "Series was offered for a live-only source")
    }
}

/// And the other way round, so the test above cannot pass for the wrong reason.
final class FullSourceTabsTests: PanopUITestCase {
    func testMoviesAndSeriesAreOffered() {
        waitForChannels()
        XCTAssertTrue(app.tabBars.buttons["Movies"].exists)
        XCTAssertTrue(app.tabBars.buttons["Series"].exists)
    }
}
