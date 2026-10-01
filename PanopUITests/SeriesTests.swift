import XCTest

final class SeriesTests: PanopUITestCase {
    override var startTab: String {
        "series"
    }

    /// The seeded playlist has three episodes of two shows. The screen lists the shows.
    func testSeriesAppearAsShowsNotEpisodes() {
        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 30), "the seeded series never appeared")
        XCTAssertTrue(app.buttons["Severance"].exists)
        XCTAssertFalse(app.buttons["Dark S01E01"].exists, "an episode is listed as if it were a show")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "series-grid"
        shot.lifetime = .keepAlways
        add(shot)
    }

    #if !os(tvOS)
        func testOpeningAShowListsItsEpisodesAndOnePlays() {
            XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 30))

            app.buttons["Dark"].tap()

            XCTAssertTrue(app.staticTexts["Season 1"].waitForExistence(timeout: 10), "no season in the detail")
            let second = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Episode 2'")).firstMatch
            XCTAssertTrue(second.exists, "the show's second episode is missing")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "series-detail"
            shot.lifetime = .keepAlways
            add(shot)

            second.tap()

            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "the episode did not open")
        }
    #endif
}
