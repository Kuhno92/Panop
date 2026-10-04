import XCTest

final class HomeHeroTests: PanopUITestCase {
    override var startTab: String {
        "home"
    }

    override var showsHero: Bool {
        true
    }

    func testHomeLeadsWithATitleAndWaysIn() {
        XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 30), "the hero did not appear")
        XCTAssertTrue(app.buttons["Play"].exists)
        XCTAssertTrue(app.buttons["More info"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "home-hero"
        shot.lifetime = .keepAlways
        add(shot)
    }

    #if !os(tvOS)
        func testASwipeMovesToTheNextTitleAndBack() {
            XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 30))

            app.staticTexts["Dune"].swipeLeft()
            XCTAssertTrue(
                app.staticTexts["Arrival"].waitForExistence(timeout: 5),
                "a swipe did not show the next title"
            )

            app.staticTexts["Arrival"].swipeRight()
            XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 5), "a swipe back did not return")
        }
    #endif
}
