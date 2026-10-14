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
        // The first demo match has a channel with the match in its title, and a second one: a choice to make.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Watch'")).firstMatch
                .waitForExistence(timeout: 30),
            "no match had a channel to watch. Screen:\n\(app.debugDescription)"
        )
        capture("sports-hub")
        XCTAssertTrue(app.staticTexts["Northern Division"].exists || app.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Harbour'")).firstMatch.exists)
    }
}

/// Without a key the Sports entry is still there: it says what is needed, and leads to where the key is entered.
final class SportsNoKeyTests: PanopUITestCase {
    override var startTab: String {
        "sports"
    }

    func testSportsIsFoundWithoutAKeyAndLeadsToTheSetting() {
        #if !os(tvOS)
            if app.tabBars.buttons["Sports"].exists {
                app.tabBars.buttons["Sports"].tap()
            } else {
                app.tabBars.buttons.element(boundBy: 0).tap()
                XCTAssertTrue(app.buttons["Sports"].waitForExistence(timeout: 15), "no Sports button on Home")
                app.buttons["Sports"].tap()
            }
            XCTAssertTrue(
                app.buttons["Enter the key"].waitForExistence(timeout: 15),
                "the hub did not say that a key is needed. Screen:\n\(app.debugDescription)"
            )
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "sports-no-key"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["Enter the key"].tap()
            XCTAssertTrue(
                app.secureTextFields["sportapi.ai key"].waitForExistence(timeout: 15),
                "the key field was not shown. Screen:\n\(app.debugDescription)"
            )
        #endif
    }
}

/// Against the real service with the developer's own key (from the git-ignored `.secrets/.sportapi`): the leagues of
/// the
/// picker are the real ones. Skipped when there is no such file, so it is no part of a normal run.
final class SportsRealServiceTests: PanopUITestCase {
    override var startTab: String {
        "sports"
    }

    override var devSportsKeyFile: String? {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".secrets/.sportapi").path
        return FileManager.default.fileExists(atPath: file) ? file : nil
    }

    func testThePickerShowsTheRealLeagues() throws {
        try XCTSkipIf(devSportsKeyFile == nil, "no key in .secrets/.sportapi")
        #if !os(tvOS)
            app.tabBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["Sports"].waitForExistence(timeout: 15))
            app.buttons["Sports"].tap()
            XCTAssertTrue(
                app.buttons["Choose leagues"].waitForExistence(timeout: 30),
                "Screen:\n\(app.debugDescription)"
            )
            app.buttons["Choose leagues"].tap()
            Thread.sleep(forTimeInterval: 8)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "sports-leagues"
            shot.lifetime = .keepAlways
            add(shot)
            XCTAssertTrue(
                app.buttons
                    .matching(
                        NSPredicate(format: "label CONTAINS[c] 'Premier League' OR label CONTAINS[c] 'Bundesliga'")
                    )
                    .firstMatch.waitForExistence(timeout: 20),
                "no real league was listed. Screen:\n\(app.debugDescription)"
            )
        #endif
    }
}
