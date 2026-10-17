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
        /// Opening search floats a field over the page. It must not rebuild the page: the carousel keeps its title.
        func testOpeningSearchLeavesTheCarouselWhereItWas() {
            XCTAssertTrue(app.staticTexts["Dune"].waitForExistence(timeout: 30))
            app.staticTexts["Dune"].swipeLeft()
            XCTAssertTrue(app.staticTexts["Arrival"].waitForExistence(timeout: 5))

            app.tabBars.buttons["Search"].tap()

            XCTAssertTrue(app.textFields["searchField"].waitForExistence(timeout: 10), "the field did not open")
            XCTAssertTrue(app.staticTexts["Arrival"].exists, "opening search sent the carousel back to its first title")
        }

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

#if os(tvOS)
    /// A stream plays behind the app: the panel down the right side must not cut into the hero's picture.
    final class HeroBesideNowPlayingTests: PanopUITestCase {
        override var startTab: String {
            "live"
        }

        override var showsHero: Bool {
            true
        }

        func testTheHeroSitsBesideThePanelWithoutBeingCut() {
            waitForChannels()
            focusFirstChannel()
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.buttons["Show stream"].waitForExistence(timeout: 10))
            for tab in ["Movies", "Series", "Home"] {
                let button = app.tabBars.buttons[tab]
                for _ in 0 ..< 6 where !button.hasFocus {
                    XCUIRemote.shared.press(.up)
                }
                for _ in 0 ..< 8 where !button.hasFocus {
                    XCUIRemote.shared.press(tab == "Home" ? .left : .right)
                }
                XCUIRemote.shared.press(.select)
                Thread.sleep(forTimeInterval: 6)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "hero-beside-panel-\(tab)"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
    }
#endif
