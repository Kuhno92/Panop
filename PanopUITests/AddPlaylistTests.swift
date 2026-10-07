import XCTest

final class AddPlaylistTests: PanopUITestCase {
    override var startTab: String {
        "settings"
    }

    /// The form opens with every field and both of its buttons on the screen. On Apple TV it used to be a small
    /// floating
    /// card that cut the form off and squeezed its title and buttons into one line.
    func testTheAddFormShowsItsFieldsAndButtons() {
        #if os(tvOS)
            sleep(2)
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Add playlist"].waitForExistence(timeout: 10), "no Add playlist row on Playlists")
            XCUIRemote.shared.press(.select)
        #else
            openSettings()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Playlists'")).firstMatch.tap()
            app.buttons["Add"].tap()
        #endif

        XCTAssertTrue(app.staticTexts["Add playlist"].waitForExistence(timeout: 10), "the form has no title")
        XCTAssertTrue(app.buttons["Cancel"].exists, "no Cancel. Screen:\n\(app.debugDescription)")
        XCTAssertTrue(app.textFields["Username"].exists || app.textFields.count >= 2, "the fields are not all there")
        #if os(tvOS)
            XCTAssertTrue(app.buttons["Add playlist"].exists, "no Add playlist button in the form")
            XCTAssertTrue(app.switches["Live TV only"].exists || app.buttons["Live TV only"].exists, "no Live TV only")
        #endif
    }
}
