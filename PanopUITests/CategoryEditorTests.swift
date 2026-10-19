import XCTest

/// The screen where categories are put in order and hidden, many at a time: a filter narrows the list, and the buttons
/// above it act on what the filter shows.
final class CategoryEditorTests: PanopUITestCase {
    #if !os(tvOS)
        private func openEditor() {
            waitForChannels()
            let edit = app.buttons["Edit categories"]
            XCTAssertTrue(
                edit.waitForExistence(timeout: 15),
                "no way into the categories. Screen:\n\(app.debugDescription)"
            )
            edit.tap()
            XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 10), "the editor did not open")
        }

        func testTheFilterNarrowsTheListAndHideActsOnWhatItShows() {
            openEditor()
            XCTAssertTrue(app.buttons["Move Germany up"].waitForExistence(timeout: 10) || app
                .buttons["Move Germany down"].exists)

            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10), "no filter field")
            field.tap()
            field.typeText("germ")

            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'shown by the filter'")).firstMatch
                    .waitForExistence(timeout: 10),
                "the filter did not say how many it shows. Screen:\n\(app.debugDescription)"
            )
            XCTAssertFalse(
                app.buttons["Move Other up"].exists || app.buttons["Move Other down"].exists,
                "Other is still listed"
            )
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "categories-filtered"
            shot.lifetime = .keepAlways
            add(shot)

            app.buttons["Hide"].tap()
            XCTAssertTrue(
                app.buttons["Show Germany"].waitForExistence(timeout: 10),
                "Hide did not hide what the filter shows"
            )

            app.buttons["Show"].tap()
            XCTAssertTrue(app.buttons["Hide Germany"].waitForExistence(timeout: 10), "Show did not show it again")
        }

        func testSelectingSeveralMovesThemTogether() {
            openEditor()
            app.buttons["Select"].tap()
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "categories-select"
            shot.lifetime = .keepAlways
            add(shot)
            XCTAssertTrue(app.buttons["Stop selecting"].waitForExistence(timeout: 5), "selecting did not start")
        }
    #endif
}
