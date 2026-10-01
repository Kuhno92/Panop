import XCTest

final class HomeTests: PanopUITestCase {
    override var startTab: String {
        "home"
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAFreshHomeOffersToBrowseLiveTV() {
        let nothing = app.staticTexts["Nothing here yet"]
        XCTAssertTrue(nothing.waitForExistence(timeout: 30), "the home screen did not appear")
        attach("home-empty")

        #if os(tvOS)
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.select)
        #else
            app.buttons["Browse Live TV"].tap()
        #endif

        XCTAssertTrue(channel("3sat").waitForExistence(timeout: 20), "Browse Live TV did not open the channel list")
    }

    #if !os(tvOS)
        func testAStarredChannelAndAPlayedOneAppearOnHome() {
            XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 30))
            app.buttons["Browse Live TV"].tap()
            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 20))

            // Star one channel, and play another.
            channel("3sat").press(forDuration: 1.2)
            app.buttons["Add to Favourites"].tap()
            XCTAssertTrue(app.images["Favourite"].waitForExistence(timeout: 10))
            channel("Arte").tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
            app.buttons["Close"].tap()

            app.tabBars.buttons["Home"].tap()

            XCTAssertTrue(app.staticTexts["Favourites"].waitForExistence(timeout: 10), "no Favourites rail")
            XCTAssertTrue(app.staticTexts["Recently watched"].exists, "no Recently watched rail")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Arte'")).firstMatch.exists)
            attach("home-rails")
        }

        func testTappingACardPlaysTheChannel() {
            XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 30))
            app.buttons["Browse Live TV"].tap()
            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 20))
            channel("3sat").tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
            app.buttons["Close"].tap()
            app.tabBars.buttons["Home"].tap()
            let card = app.buttons.matching(NSPredicate(format: "label CONTAINS '3sat'")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10), "the channel just watched is not on Home")

            card.tap()

            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15), "the card did not open the player")
        }
    #endif
}
