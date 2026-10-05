import XCTest

final class PlayerTests: PanopUITestCase {
    private func openFirstChannel() {
        waitForChannels()
        #if os(tvOS)
            focusFirstChannel()
            XCUIRemote.shared.press(.select)
        #else
            channel("3sat").tap()
        #endif
    }

    /// Fails with the screen's contents, which is the only clue to why a player never came up.
    private func waitForPlayerControls(file: StaticString = #filePath, line: UInt = #line) {
        let shown = app.buttons["Pause"].waitForExistence(timeout: 15)
        XCTAssertTrue(
            shown,
            "the player did not show its controls. Screen:\n\(app.debugDescription)",
            file: file,
            line: line
        )
    }

    func testAChannelOpensWithControlsAndALiveBadge() {
        openFirstChannel()

        waitForPlayerControls()
        XCTAssertTrue(app.staticTexts["Live"].exists, "a channel is live, so there is no scrubber")
        XCTAssertTrue(app.buttons["Audio"].exists, "two audio tracks should offer a menu")
        XCTAssertTrue(app.buttons["Subtitles"].exists)
        XCTAssertTrue(app.staticTexts["playerClock"].exists, "the time of day is not shown with the controls")
    }

    func testPausingChangesTheButtonToPlay() {
        openFirstChannel()
        waitForPlayerControls()

        #if os(tvOS)
            XCUIRemote.shared.press(.select)
        #else
            app.buttons["Pause"].tap()
        #endif

        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    }

    #if os(tvOS)
        /// The fix this target was added to check: the bar must not vanish under the remote
        /// while a control has focus, which it did, taking the focus with it.
        func testControlsStayUpWhileTheRemoteHasFocusOnThem() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))

            // Well past the four seconds the bar would otherwise last.
            Thread.sleep(forTimeInterval: 8)

            XCTAssertTrue(app.buttons["Pause"].exists, "the controls hid while one of them had focus")
        }

        func testMenuClosesThePlayer() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))

            XCUIRemote.shared.press(.menu)

            XCTAssertTrue(app.buttons["Pause"].waitForNonExistence(timeout: 10))
            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 10))
        }
    #else
        func testCloseReturnsToTheList() {
            openFirstChannel()
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 15))

            close.tap()

            XCTAssertTrue(close.waitForNonExistence(timeout: 10))
            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 10))
        }
    #endif
}

#if !os(tvOS)
    /// The controls hide on their own, so this one asks for the short timeout.
    final class ControlsAutoHideTests: PanopUITestCase {
        override var controlsTimeout: Int {
            3
        }

        func testControlsHideOnTheirOwnAndATapBringsThemBack() {
            waitForChannels()
            channel("3sat").tap()
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 15))

            // Three seconds after the first picture, with nothing touched.
            XCTAssertTrue(close.waitForNonExistence(timeout: 12), "the controls never hid")

            // Where a person would: the middle of the picture.
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5), "a tap did not bring the controls back")
        }

        func testTheControlsStayUpWhileAnAudioMenuIsOpen() {
            waitForChannels()
            channel("3sat").tap()
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 15))

            app.buttons["Audio"].tap()
            let english = app.buttons["English"]
            XCTAssertTrue(english.waitForExistence(timeout: 10), "the audio choices did not open")

            // Twice the timeout and more: the bar would have gone, and the menu with it.
            Thread.sleep(forTimeInterval: 7)
            XCTAssertTrue(english.exists, "the open menu went with the controls")
            XCTAssertTrue(close.exists, "the controls hid while a menu was open")

            // Choosing closes it, and then the bar goes on its own again.
            english.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 12), "the controls never hid after the menu closed")
        }
    }
#endif
