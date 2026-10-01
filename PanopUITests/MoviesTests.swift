import XCTest

final class MoviesTests: PanopUITestCase {
    override var startTab: String {
        "movies"
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func poster(_ name: String) -> XCUIElement {
        app.buttons[name]
    }

    func testMoviesShowAsPosters() {
        XCTAssertTrue(poster("Alien").waitForExistence(timeout: 30), "the seeded films never appeared")
        XCTAssertTrue(poster("Blade Runner").exists)
        attach("movies-grid")
    }

    #if !os(tvOS)
        func testAFilmLeftPartWayOffersToResume() {
            XCTAssertTrue(poster("Alien").waitForExistence(timeout: 30))
            poster("Alien").tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "the film did not open")
            XCTAssertTrue(app.buttons["Back 10 seconds"].exists, "a film has a scrubber, not a LIVE badge")

            // Long enough that there is somewhere to resume from (nothing under ten seconds is kept).
            Thread.sleep(forTimeInterval: 13)
            app.buttons["Close"].tap()
            XCTAssertTrue(poster("Alien").waitForExistence(timeout: 10))

            poster("Alien").tap()
            let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume from'")).firstMatch
            XCTAssertTrue(resume.waitForExistence(timeout: 10), "no offer to resume")
            attach("movies-resume-dialog")
            resume.tap()

            XCTAssertTrue(app.buttons["Back 10 seconds"].waitForExistence(timeout: 15))
            // The test engine starts where it was asked to: a start from zero would read 0:0x.
            let elapsed = app.staticTexts.matching(NSPredicate(format: "label MATCHES '0:(1|2)\\\\d'")).firstMatch
            XCTAssertTrue(elapsed.waitForExistence(timeout: 10), "it did not resume from where it was left")
        }

        func testStartingOverIgnoresTheSavedPoint() {
            XCTAssertTrue(poster("Blade Runner").waitForExistence(timeout: 30))
            poster("Blade Runner").tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 13)
            app.buttons["Close"].tap()
            poster("Blade Runner").tap()
            XCTAssertTrue(app.buttons["Start over"].waitForExistence(timeout: 10))

            app.buttons["Start over"].tap()

            XCTAssertTrue(app.buttons["Back 10 seconds"].waitForExistence(timeout: 15))
            let early = app.staticTexts.matching(NSPredicate(format: "label MATCHES '0:0\\\\d'")).firstMatch
            XCTAssertTrue(early.waitForExistence(timeout: 10), "starting over did not begin at the start")
        }
    #endif
}
