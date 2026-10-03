import XCTest

/// The app in German: what is drawn comes from the string catalog, so a missing or wrong key shows here
/// as English text where German should be.
final class LocalisationTests: PanopUITestCase {
    override var startTab: String {
        "home"
    }

    override var launchLanguage: String? {
        "de"
    }

    func testTheTabsAndTheEmptyHomeAreInGerman() {
        XCTAssertTrue(
            app.staticTexts["Noch nichts hier"].waitForExistence(timeout: 30),
            "Home is not in German. Screen:\n\(app.debugDescription)"
        )
        #if !os(tvOS)
            XCTAssertTrue(app.tabBars.buttons["Einstellungen"].exists, "the Settings tab is not in German")
            XCTAssertTrue(app.tabBars.buttons["Live-TV"].exists)
            XCTAssertTrue(app.tabBars.buttons["Filme"].exists)
            XCTAssertTrue(app.tabBars.buttons["Serien"].exists)
        #endif
    }

    #if !os(tvOS)
        func testSettingsAndWhatIsBuiltInCodeAreInGerman() {
            XCTAssertTrue(app.staticTexts["Noch nichts hier"].waitForExistence(timeout: 30))
            app.tabBars.buttons["Einstellungen"].tap()

            XCTAssertTrue(
                app.staticTexts["Mediathek"].waitForExistence(timeout: 10),
                "a section header is not in German"
            )
            XCTAssertTrue(app.switches["Inhalte für Erwachsene ausblenden"].exists, "a toggle is not in German")

            // Sorting names come from code, not from a literal in a view.
            app.tabBars.buttons["Live-TV"].tap()
            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 20))
            app.buttons["Sortieren"].tap()
            XCTAssertTrue(
                app.buttons["Nach Name"].waitForExistence(timeout: 10),
                "a name built in code is not in German"
            )
        }
    #endif
}
