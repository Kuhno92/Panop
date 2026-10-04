import XCTest

final class ProfilesTests: PanopUITestCase {
    #if !os(tvOS)
        private func scrollTo(_ element: XCUIElement) {
            for _ in 0 ..< 6 where !element.exists {
                app.swipeUp()
            }
        }

        func testEachProfileHasItsOwnFavourites() {
            waitForChannels()
            channel("3sat").press(forDuration: 1.2)
            app.buttons["Add to Favourites"].tap()
            XCTAssertTrue(app.images["Favourite"].waitForExistence(timeout: 10))

            openSettings()
            app.buttons["Profiles, Main"].tap()
            app.buttons["Add profile…"].tap()
            let field = app.alerts.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10), "no name field. Screen:\n\(app.debugDescription)")
            field.typeText("Kids")
            app.alerts.buttons["Add"].tap()
            // A row's label also names its icons, such as "Kids, Adult content hidden".
            let kids = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kids'")).firstMatch
            XCTAssertTrue(kids.waitForExistence(timeout: 10), "the new profile is not listed")
            kids.tap()

            // The new profile has nothing yet; the first one still has its favourite.
            app.tabBars.buttons["Home"].tap()
            XCTAssertTrue(
                app.staticTexts["Nothing here yet"].waitForExistence(timeout: 15),
                "Kids should have no favourites. Screen:\n\(app.debugDescription)"
            )
            XCTAssertFalse(app.staticTexts["Favourites"].exists)

            app.buttons["Profile"].tap()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Main'")).firstMatch.tap()
            XCTAssertTrue(
                app.staticTexts["Favourites"].waitForExistence(timeout: 15),
                "the first profile lost its favourite"
            )
        }
    #endif
}
