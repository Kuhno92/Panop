import XCTest

/// Channels that share a guide are listed once (the first of them), with a button to choose another version, and the
/// player offers the same choice. The seeded playlist has "Das Erste" and "Das Erste HD" on one guide.
final class VersionsTests: PanopUITestCase {
    override var groupsByGuide: Bool {
        true
    }

    private var dasErsteRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Das Erste'"))
    }

    func testTheListShowsOneChannelPerGuideWithAMenuToChooseAnother() {
        waitForChannels()
        XCTAssertTrue(
            app.buttons["channelVersions"].firstMatch.waitForExistence(timeout: 15),
            "no button to choose a version"
        )
        XCTAssertEqual(dasErsteRows.count, 1, "the second version is listed as a channel of its own")

        #if os(tvOS)
            focusFirstChannel()
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.select)
        #else
            app.buttons["channelVersions"].firstMatch.tap()
        #endif

        #if os(tvOS)
            // An item of Apple TV's menu is not a button to the accessibility tree.
            let other = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Das Erste HD'"))
                .firstMatch
        #else
            let other = app.buttons["Das Erste HD"]
        #endif
        XCTAssertTrue(other.waitForExistence(timeout: 10), "the other version is not offered")
        #if os(tvOS)
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.select)
        #else
            other.tap()
        #endif
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15), "the chosen version did not play")
        XCTAssertTrue(app.staticTexts["Das Erste HD"].exists, "the player is not on the version that was chosen")
    }

    #if !os(tvOS)
        func testThePlayerOffersTheVersionsAndSwitches() {
            waitForChannels()
            channel("Das Erste").tap()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))

            let version = app.buttons["Version"]
            XCTAssertTrue(version.waitForExistence(timeout: 15), "no version choice in the controls")
            version.tap()
            app.buttons["Das Erste HD"].tap()

            XCTAssertTrue(app.staticTexts["Das Erste HD"].waitForExistence(timeout: 15), "the player did not switch")
        }

        func testTheChoiceIsRemembered() {
            waitForChannels()
            app.buttons["channelVersions"].firstMatch.tap()
            app.buttons["Das Erste HD"].tap()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))
            app.buttons["Close"].tap()

            // Choosing the row itself now plays what was chosen.
            channel("Das Erste").tap()

            XCTAssertTrue(
                app.staticTexts["Das Erste HD"].waitForExistence(timeout: 15),
                "the choice was not remembered"
            )
        }
    #endif
}
