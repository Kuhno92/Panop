import XCTest

/// The sports hub with the demo service (invented clubs): the screens are driven and looked at, with no network.
class SportsScene: PanopUITestCase {
    override var demoSports: Bool {
        true
    }

    override var startTab: String {
        "sports"
    }

    /// The hub: its tab where there is one, and on a compact phone the button on Home.
    func openHub() {
        #if os(tvOS)
            // The tab bar has focus first; the Sports tab is the one named so.
            XCUIRemote.shared.press(.select)
        #else
            if !app.tabBars.buttons["Sports"].exists {
                app.tabBars.buttons.element(boundBy: 0).tap()
                app.buttons["Sports"].tap()
            } else {
                app.tabBars.buttons["Sports"].tap()
            }
        #endif
    }

    func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

final class SportsHubTests: SportsScene {
    func testHubShowsTodaysMatches() {
        openHub()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Northgate'")).firstMatch
                .waitForExistence(timeout: 30),
            "the demo matches never appeared. Screen:\n\(app.debugDescription)"
        )
        capture("sports-hub")
        XCTAssertTrue(app.staticTexts["Northern Division"].exists || app.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Harbour'")).firstMatch.exists)
    }
}
