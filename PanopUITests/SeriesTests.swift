import XCTest

final class SeriesTests: PanopUITestCase {
    override var startTab: String {
        "series"
    }

    func testSeriesAppearAsPosters() {
        XCTAssertTrue(app.buttons["Dark S01E01"].waitForExistence(timeout: 30), "the seeded series never appeared")
        XCTAssertTrue(app.buttons["Severance S01E01"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "series-grid"
        shot.lifetime = .keepAlways
        add(shot)
    }

    #if !os(tvOS)
        /// An M3U "series" entry is one episode with its own address, so it plays at once.
        func testAnM3UEpisodePlaysDirectly() {
            XCTAssertTrue(app.buttons["Dark S01E01"].waitForExistence(timeout: 30))

            app.buttons["Dark S01E01"].tap()

            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "the episode did not open")
        }
    #endif
}
