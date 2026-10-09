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

    #if os(tvOS)
        /// Whether `element` takes the focus within a couple of seconds: it moves with an animation. Apple TV only:
        /// `hasFocus` is not in the macOS SDK the CI runner builds against.
        private func hasFocusSoon(_ element: XCUIElement) -> Bool {
            for _ in 0 ..< 20 {
                if element.exists, element.hasFocus {
                    return true
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            return false
        }
    #endif

    // Fails with the screen's contents, which is the only clue to why a player never came up.

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
            XCTAssertTrue(app.buttons["Show stream"].exists, "nothing says a stream is still playing")
            XCTAssertTrue(app.buttons["Stop"].exists, "no Stop in the bar over the app")

            // Back at the app the focus is on the bar, so Select shows the stream.
            XCUIRemote.shared.press(.select)

            // The stream is in front again: the bar over the app is gone (the controls may have timed out already).
            XCTAssertTrue(
                app.buttons["Show stream"].waitForNonExistence(timeout: 10),
                "Select on the bar did not bring the stream back"
            )
        }

        /// The panel with Show stream and Stop is down the right side, and the right arrow reaches it from the list.
        func testTheRightArrowReachesTheNowPlayingPanel() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))
            XCUIRemote.shared.press(.menu)
            let show = app.buttons["Show stream"]
            XCTAssertTrue(show.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Stop"].exists)

            // Into the list, and back to the panel with the right arrow alone.
            XCUIRemote.shared.press(.left)
            XCTAssertFalse(show.hasFocus, "the left arrow did not leave the panel")
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(show.hasFocus, "the right arrow did not reach the panel")

            XCUIRemote.shared.press(.select)
            XCTAssertTrue(
                app.buttons["Show stream"].waitForNonExistence(timeout: 10),
                "Show stream did not bring the stream back"
            )
        }

        /// The guide button in the stream's controls opens the TV guide over the stream (it used to go back to the
        /// menu), and
        /// Menu closes the guide and leaves the stream.
        func testTheGuideButtonOpensTheGuideOverTheStream() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))

            let guide = app.buttons["playerGuide"]
            XCTAssertTrue(guide.exists, "no guide button in the controls")
            for _ in 0 ..< 6 where !(guide.exists && guide.hasFocus) {
                XCUIRemote.shared.press(.right)
            }
            XCUIRemote.shared.press(.select)

            XCTAssertTrue(
                app.staticTexts["TV Guide"].waitForExistence(timeout: 10),
                "the guide did not open. Screen:\n\(app.debugDescription)"
            )
            XCTAssertFalse(app.buttons["Show stream"].exists, "it went back to the menu instead")

            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(
                app.buttons["Pause"].waitForExistence(timeout: 10),
                "Menu did not leave the guide for the stream"
            )
        }

        /// Down from Show stream is Stop, and Stop ends the stream: the panel goes and nothing plays on.
        func testStopIsReachedFromShowStream() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))
            XCUIRemote.shared.press(.menu)
            let show = app.buttons["Show stream"]
            XCTAssertTrue(show.waitForExistence(timeout: 10))
            XCTAssertTrue(show.hasFocus)

            XCUIRemote.shared.press(.down)
            XCTAssertTrue(app.buttons["Stop"].hasFocus, "Down from Show stream did not reach Stop")
            XCUIRemote.shared.press(.up)
            XCTAssertTrue(show.hasFocus, "Up from Stop did not go back to Show stream")

            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(show.waitForNonExistence(timeout: 10), "Stop did not end the stream")
        }

        /// The right arrow goes to the panel only when nothing on the screen is further right: along the row of buttons
        /// ("All channels", "Favourites", "Recently watched") it moves between them first.
        func testTheRightArrowIsTheLastOptionBeforeThePanel() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.buttons["Show stream"].waitForExistence(timeout: 10))

            // Into the list, and up to the first of the row of buttons.
            XCUIRemote.shared.press(.left)
            let all = app.buttons["All channels"]
            for _ in 0 ..< 10 where !(all.exists && all.hasFocus) {
                XCUIRemote.shared.press(.up)
            }
            XCTAssertTrue(all.hasFocus, "could not get to the row of buttons. Screen:\n\(app.debugDescription)")

            XCUIRemote.shared.press(.right)
            XCTAssertTrue(
                hasFocusSoon(app.buttons["Favourites"]),
                "the first right press did not move along the buttons"
            )
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(
                hasFocusSoon(app.buttons["Recently watched"]),
                "the second right press did not move along the buttons"
            )
            XCTAssertFalse(app.buttons["Show stream"].hasFocus, "the panel took the right arrow too early")

            XCUIRemote.shared.press(.right)
            XCTAssertTrue(
                hasFocusSoon(app.buttons["Show stream"]),
                "from the last button the right arrow did not reach the panel"
            )
        }

        /// Back in the stream, the Back button (Menu) opens the app again and does not close it.
        func testMenuStillGoesBackToTheAppAfterShowingTheStream() {
            openFirstChannel()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.buttons["Show stream"].waitForExistence(timeout: 10))
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Show stream"].waitForNonExistence(timeout: 10), "the stream did not come back")

            XCUIRemote.shared.press(.menu)

            XCTAssertTrue(
                app.buttons["Show stream"].waitForExistence(timeout: 10),
                "Menu did not return to the app after the stream was shown again"
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
