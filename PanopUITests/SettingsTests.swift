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

            app.tabBars.buttons["Settings"].tap()
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

        func testAStartupChannelCanBeChosen() {
            waitForChannels()
            app.tabBars.buttons["Settings"].tap()

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

            app.tabBars.buttons["Settings"].tap()
            openPlaybackStatistics()

            XCTAssertTrue(app.staticTexts["Nothing yet"].waitForExistence(timeout: 10))
        }
    #endif
}
