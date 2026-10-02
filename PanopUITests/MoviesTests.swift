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

    func testTheProvidersCategoriesAreChipsAboveTheFilms() {
        XCTAssertTrue(poster("Alien").waitForExistence(timeout: 30))

        XCTAssertTrue(app.buttons["All"].waitForExistence(timeout: 10), "no category chips")
        XCTAssertTrue(app.buttons["Films"].exists, "the source's category is not a chip")
        XCTAssertTrue(app.buttons["Classics"].exists, "the source's other category is not a chip")
    }

    func testFilmsAreShownUnderTheirCategoryHeadings() {
        XCTAssertTrue(poster("Alien").waitForExistence(timeout: 30))

        // A heading for each category, as well as the chip that narrows to it.
        XCTAssertTrue(app.staticTexts["Films"].waitForExistence(timeout: 10), "no heading for the first category")
        XCTAssertTrue(app.staticTexts["Classics"].exists, "no heading for the second category")
    }

    #if !os(tvOS)
        func testTheSortOffersWhatFilmsCanBeSortedBy() {
            XCTAssertTrue(poster("Alien").waitForExistence(timeout: 30))

            app.buttons["Sort"].tap()

            XCTAssertTrue(app.buttons["Recently added"].waitForExistence(timeout: 10), "no sort by date added")
            XCTAssertTrue(app.buttons["By name"].exists)
            XCTAssertTrue(app.buttons["Top rated"].exists)
            XCTAssertTrue(app.buttons["Provider's order"].exists)
        }

        func testChoosingACategoryShowsOnlyItsHeading() {
            XCTAssertTrue(poster("Alien").waitForExistence(timeout: 30))

            app.buttons["Classics"].tap()

            XCTAssertTrue(poster("Dune").waitForExistence(timeout: 10), "the chosen category's film is missing")
            XCTAssertTrue(poster("Alien").waitForNonExistence(timeout: 10), "another category's film is still there")
        }

        func testOpeningAFilmShowsItsPage() {
            XCTAssertTrue(poster("Dune").waitForExistence(timeout: 30))
            poster("Dune").tap()

            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10), "no Play button on the film's page")
            XCTAssertTrue(app.staticTexts["Dune"].exists, "the title is not on the page")
            XCTAssertTrue(app.buttons["Add to Favourites"].exists)
            XCTAssertTrue(app.buttons["Mark as Watched"].exists)
            attach("movie-page")
        }

        func testAFilmLeftPartWayOffersToResume() {
            XCTAssertTrue(poster("Alien").waitForExistence(timeout: 30))
            poster("Alien").tap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10), "the film's page did not open")
            app.buttons["Play"].tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "the film did not open")
            XCTAssertTrue(app.buttons["Back 10 seconds"].exists, "a film has a scrubber, not a LIVE badge")

            // Long enough that there is somewhere to resume from (nothing under ten seconds is kept).
            Thread.sleep(forTimeInterval: 13)
            app.buttons["Close"].tap()

            // Closing the player returns to the film's page, which now offers where it was left.
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
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10), "the film's page did not open")
            app.buttons["Play"].tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 13)
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Start over"].waitForExistence(timeout: 10))

            app.buttons["Start over"].tap()

            XCTAssertTrue(app.buttons["Back 10 seconds"].waitForExistence(timeout: 15))
            let early = app.staticTexts.matching(NSPredicate(format: "label MATCHES '0:0\\\\d'")).firstMatch
            XCTAssertTrue(early.waitForExistence(timeout: 10), "starting over did not begin at the start")
        }
    #endif
}
