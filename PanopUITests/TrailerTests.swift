import XCTest

/// The Trailer button plays the trailer in the app. The seeded films have no panel to give one, so the app is given a
/// known
/// video (Blender's Big Buck Bunny, which allows embedding) as the trailer of every film.
final class TrailerTests: PanopUITestCase {
    override var startTab: String {
        "movies"
    }

    override var trailerID: String? {
        "aqz-KE-bpKQ"
    }

    func testTheTrailerPlaysInTheApp() {
        let film = app.buttons["Alien"]
        XCTAssertTrue(film.waitForExistence(timeout: 30), "the seeded films never appeared")
        #if os(tvOS)
            focus(film)
            XCUIRemote.shared.press(.select)
        #else
            film.tap()
        #endif
        let trailer = app.buttons["Trailer"]
        XCTAssertTrue(
            trailer.waitForExistence(timeout: 20),
            "no Trailer button on the film's page. Screen:\n\(app.debugDescription)"
        )
        #if os(tvOS)
            focus(trailer)
            XCUIRemote.shared.press(.select)
        #else
            trailer.tap()
        #endif
        // Time for the page, the player and the first frames.
        Thread.sleep(forTimeInterval: 30)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "trailer"
        shot.lifetime = .keepAlways
        add(shot)
        // The film's own page is behind the player: still there, and no browser was opened over the app.
        XCTAssertEqual(app.state, .runningForeground)
    }
}
