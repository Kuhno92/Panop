import XCTest

final class SettingsTests: PanopUITestCase {
    #if !os(tvOS)
        /// Settings is a long list, and a row below the fold is not in the accessibility tree yet.
        private func openPlaybackStatistics() {
            let row = app.buttons["Playback Statistics"]
            for _ in 0 ..< 5 where !row.exists {
                app.swipeUp()
            }
            row.tap()
        }

        func testPlayingAChannelShowsUpInThePlaybackStatistics() {
            waitForChannels()
            channel("3sat").tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 3)
            app.buttons["Close"].tap()

            openSettings()
            openPlaybackStatistics()

            XCTAssertTrue(
                app.staticTexts["Viewing sessions"].waitForExistence(timeout: 10),
                "no statistics after a session"
            )
            XCTAssertTrue(app.staticTexts["AVPlayer"].exists, "the engine that played is not listed")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "settings-statistics"
            shot.lifetime = .keepAlways
            add(shot)
        }

        /// Types into the PIN field the sheet has focused and presses Continue.
        private func enterPIN(_ digits: String) {
            let field = app.secureTextFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10), "no PIN field. Screen:\n\(app.debugDescription)")
            field.tap()
            field.typeText(digits)
            app.buttons["Continue"].tap()
        }

        private func scrollTo(_ element: XCUIElement) {
            for _ in 0 ..< 6 where !element.exists {
                app.swipeUp()
            }
        }

        func testAPINGuardsTurningTheAdultFilterOff() {
            waitForChannels()
            openSettings()
            let setPIN = app.buttons["Set a PIN…"]
            scrollTo(setPIN)
            setPIN.tap()
            enterPIN("4821")
            enterPIN("4821")
            XCTAssertTrue(app.buttons["Change PIN…"].waitForExistence(timeout: 10), "the PIN was not set")

            let toggle = app.switches["Hide adult content"]
            scrollTo(toggle)
            XCTAssertEqual(toggle.value as? String, "1", "the filter should be on")
            // The row is wide, but only the switch at its right edge responds.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

            // Asked for the PIN: a wrong one is refused and the filter stays on.
            enterPIN("1111")
            XCTAssertTrue(app.staticTexts["Wrong PIN. 4 tries left."].waitForExistence(timeout: 10))
            enterPIN("4821")
            XCTAssertTrue(app.buttons["Change PIN…"].waitForExistence(timeout: 10), "the sheet did not close")
            scrollTo(toggle)
            XCTAssertEqual(toggle.value as? String, "0", "the right PIN did not turn the filter off")
        }

        func testSubtitlesCanBeStyledAndResetToStandard() {
            waitForChannels()
            openSettings()
            let link = app.buttons["Subtitles"]
            scrollTo(link)
            link.tap()

            let raise = app.switches["Raise subtitles"]
            XCTAssertTrue(raise.waitForExistence(timeout: 10), "no subtitle settings. Screen:\n\(app.debugDescription)")
            XCTAssertEqual(raise.value as? String, "0")

            raise.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            XCTAssertEqual(raise.value as? String, "1", "the setting did not change")

            let reset = app.buttons["Reset to standard"]
            XCTAssertTrue(reset.waitForExistence(timeout: 10))
            reset.tap()
            XCTAssertEqual(raise.value as? String, "0", "reset did not restore the standard look")
        }

        func testAStartupChannelCanBeChosen() {
            waitForChannels()
            openSettings()

            let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS 'When Panop opens'")).firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 10), "no startup setting. Screen:\n\(app.debugDescription)")
            picker.tap()
            app.buttons["Play a channel"].tap()

            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Channel'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "choosing a channel to play did not offer to pick one")
            row.tap()
            XCTAssertTrue(app.buttons["3sat"].waitForExistence(timeout: 10), "the channel list did not appear")
            app.buttons["3sat"].tap()

            let chosen = app.buttons.matching(NSPredicate(format: "label CONTAINS '3sat'")).firstMatch
            XCTAssertTrue(chosen.waitForExistence(timeout: 10), "the chosen channel is not shown in Settings")
        }

        func testWithNothingPlayedTheStatisticsSaySo() {
            waitForChannels()

            openSettings()
            openPlaybackStatistics()

            XCTAssertTrue(app.staticTexts["Nothing yet"].waitForExistence(timeout: 10))
        }
    #endif
}
