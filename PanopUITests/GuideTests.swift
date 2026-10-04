import XCTest

final class GuideTests: PanopUITestCase {
    /// A programme's cell on the grid: its label is the title, then its times and channel.
    private func programme(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title),")).firstMatch
    }

    private func openGuide() {
        waitForChannels()
        #if os(tvOS)
            // Down from the tab bar reaches the search magnifier, then the TV Guide button.
            focusButton(labelled: "TV Guide")
            XCUIRemote.shared.press(.select)
        #else
            app.buttons["TV Guide"].tap()
        #endif
        XCTAssertTrue(
            programme("Seeded News").waitForExistence(timeout: 20),
            "the guide grid did not show what is on. Screen:\n\(app.debugDescription)"
        )
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "guide-grid"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTheGridShowsWhatIsOnAndWhatComesNextForSeveralChannels() {
        openGuide()

        // What is on now, on four channels, and what follows on them.
        for title in ["Seeded News", "Morning Magazine", "Sunrise Talk", "Art Documentary"] {
            XCTAssertTrue(programme(title).waitForExistence(timeout: 10), "\(title) is not on the grid")
        }
        for title in ["Seeded Film", "Quiz Night", "Crime Series", "Opera Evening", "Seeded Late Show"] {
            XCTAssertTrue(programme(title).exists, "\(title), coming up, is not on the grid")
        }
    }

    #if !os(tvOS)
        func testAFutureProgrammeOpensItsDetailsAndTheChannelCanBeWatchedFromThere() {
            openGuide()

            programme("Seeded Film").tap()

            XCTAssertTrue(
                app.staticTexts["Seeded Film"].waitForExistence(timeout: 10),
                "the programme's details did not open. Screen:\n\(app.debugDescription)"
            )
            XCTAssertTrue(app.buttons["Channel schedule"].exists)
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Watch 3sat'")).firstMatch.tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "the channel did not play")
        }

        func testTheChannelCellPlaysTheChannel() {
            openGuide()

            app.buttons["Watch 3sat"].tap()

            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "the channel did not play")
        }

        func testARowSaysWhatComesNextAsWellAsWhatIsOn() {
            waitForChannels()

            let next = app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH 'Next:' AND label CONTAINS 'Seeded Film'"))
            XCTAssertTrue(
                next.firstMatch.waitForExistence(timeout: 15),
                "the row for a channel with a guide does not say what is next. Screen:\n\(app.debugDescription)"
            )
        }
    #endif

    #if os(tvOS)
        /// The schedule of one channel, from the menu on its row: the part of the guide that was only
        /// ever tried on a phone.
        func testTheChannelScheduleOpensFromTheRowMenuOnAppleTV() {
            waitForChannels()
            focusFirstChannel() // Das Erste
            XCUIRemote.shared.press(.down) // ZDF
            XCUIRemote.shared.press(.down) // 3sat
            XCUIRemote.shared.press(.select, forDuration: 1.5)
            // The menu opens on its first item; Programme Guide is the second.
            // The menu's items are plain elements on Apple TV, not buttons.
            let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Programme Guide'"))
                .firstMatch
            XCTAssertTrue(
                item.waitForExistence(timeout: 10),
                "the row's menu did not open. Screen:\n\(app.debugDescription)"
            )
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.select)

            XCTAssertTrue(
                app.staticTexts["Seeded Film"].waitForExistence(timeout: 10),
                "the channel's schedule did not open. Screen:\n\(app.debugDescription)"
            )
        }
    #endif
}
