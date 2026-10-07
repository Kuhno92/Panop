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

        // The seeded guide: what is on now, with its times, and what follows. Apple TV opens the first channel in the
        // list and the other platforms open 3sat, each with a guide of its own.
        let programme = app.descendants(matching: .any)["liveProgramme"].firstMatch
        XCTAssertTrue(
            programme.waitForExistence(timeout: 10),
            "no programme in the controls. Screen:\n\(app.debugDescription)"
        )
        #if os(tvOS)
            let (now, next) = ("Morning Magazine", "Quiz Night")
        #else
            let (now, next) = ("Seeded News", "Seeded Film")
        #endif
        XCTAssertTrue(programme.label.contains(now), "the programme on now is missing: \(programme.label)")
        XCTAssertTrue(programme.label.contains(next), "the programme that follows is missing: \(programme.label)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "player-programme"
        shot.lifetime = .keepAlways
        add(shot)
    }

    #if !os(tvOS)
        /// The guide opens over the stream, and choosing a channel in it switches the stream to that channel.
        func testTheGuideOpensFromThePlayerAndSwitchesChannel() {
            openFirstChannel()
            waitForPlayerControls()

            XCTAssertTrue(app.buttons["playerGuide"].exists, "no TV Guide in the player's controls")
            app.buttons["playerGuide"].tap()
            let news = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Seeded News,")).firstMatch
            XCTAssertTrue(
                news.waitForExistence(timeout: 20),
                "the guide did not open over the stream. Screen:\n\(app.debugDescription)"
            )

            app.buttons["Watch Arte"].tap()
            waitForPlayerControls()
            XCTAssertTrue(app.staticTexts["Arte"].waitForExistence(timeout: 10), "the stream did not switch to Arte")
        }
    #endif

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

        /// Menu goes back to the app and the stream plays on behind it, as on a Mac. Select on the bar over the app
        /// (where the
        /// focus lands) brings it forward again, and Stop in the bar over the app ends it.
        func testMenuSendsTheStreamBehindTheApp() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))

            XCUIRemote.shared.press(.menu)

            XCTAssertTrue(app.buttons["Pause"].waitForNonExistence(timeout: 10), "the controls stayed over the app")
            XCTAssertTrue(channel("3sat").waitForExistence(timeout: 10), "the app is not back")
            XCTAssertTrue(app.staticTexts["Now playing"].exists, "nothing says a stream is still playing")
            XCTAssertTrue(app.buttons["Stop"].exists, "no Stop in the bar over the app")

            // Back at the app the focus is on the bar, so Select shows the stream.
            XCUIRemote.shared.press(.select)

            // The stream is in front again: the bar over the app is gone (the controls may have timed out already).
            XCTAssertTrue(
                app.staticTexts["Now playing"].waitForNonExistence(timeout: 10),
                "Select on the bar did not bring the stream back"
            )
        }

        /// From anywhere in the app, an icon in the tab bar brings the stream back: the bar over the app is at the
        /// bottom
        /// of the screen, which the remote cannot reach once the focus has moved up into a long list.
        func testTheTabBarBringsTheStreamBack() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.staticTexts["Now playing"].waitForExistence(timeout: 10))

            // Up to the tab bar, along it to the Now playing icon, and Select.
            let live = app.buttons["Live TV"].firstMatch
            for _ in 0 ..< 15 where !live.hasFocus {
                XCUIRemote.shared.press(.up)
            }
            let icon = app.buttons["Now playing"].firstMatch
            XCTAssertTrue(icon.exists, "no Now playing icon in the tab bar. Screen:\n\(app.debugDescription)")
            for _ in 0 ..< 6 where !icon.hasFocus {
                XCUIRemote.shared.press(.right)
            }
            XCUIRemote.shared.press(.select)

            XCTAssertTrue(
                app.staticTexts["Now playing"].waitForNonExistence(timeout: 10),
                "the stream did not come back"
            )

            // The stream is in front with its controls up, and the last of them takes the focus to the app again: the
            // arrows
            // reach it, whatever the Menu button does.
            let menu = app.buttons["playerMenu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10), "no Menu button in the player's controls")
            for _ in 0 ..< 8 where !menu.hasFocus {
                XCUIRemote.shared.press(.right)
            }
            XCTAssertTrue(menu.hasFocus, "the right arrow did not reach the Menu button")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(
                app.staticTexts["Now playing"].waitForExistence(timeout: 10),
                "the Menu button did not go back to the app"
            )
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
