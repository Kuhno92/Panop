import XCTest

final class SettingsTests: PanopUITestCase {
    #if !os(tvOS)
        func testPlayingAChannelShowsUpInThePlaybackStatistics() {
            waitForChannels()
            channel("3sat").tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 3)
            app.buttons["Close"].tap()

            app.tabBars.buttons["Settings"].tap()
            app.buttons["Playback Statistics"].tap()

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

        func testWithNothingPlayedTheStatisticsSaySo() {
            waitForChannels()

            app.tabBars.buttons["Settings"].tap()
            app.buttons["Playback Statistics"].tap()

            XCTAssertTrue(app.staticTexts["Nothing yet"].waitForExistence(timeout: 10))
        }
    #endif
}
