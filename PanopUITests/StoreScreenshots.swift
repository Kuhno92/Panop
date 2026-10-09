import XCTest

/// Takes the screenshots for the App Store, on whatever device the run is on (`Scripts/make-store-screenshots.sh`).
/// They
/// show the fictional demo content (`DemoContent`), so no one else's artwork or logo is on them. Each scene is a class
/// of
/// its own because each opens the app on a different screen.
class StoreScene: PanopUITestCase {
    override var isDemo: Bool {
        true
    }

    override var showsHero: Bool {
        true
    }

    /// Lets the generated artwork draw before the picture is taken.
    func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 4)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

final class StoreHomeScene: StoreScene {
    override var startTab: String {
        "home"
    }

    func testHome() {
        XCTAssertTrue(app.staticTexts["Sintel"].waitForExistence(timeout: 30))
        capture("01-home")
    }
}

final class StoreLiveScene: StoreScene {
    func testLive() {
        XCTAssertTrue(channel("Panop News").waitForExistence(timeout: 30))
        capture("02-live")
    }

    // Not on Apple TV, where the focus has to be walked to the guide button and a press there starts a channel instead.
    #if !os(tvOS)
        func testGuide() {
            XCTAssertTrue(channel("Panop News").waitForExistence(timeout: 30))
            #if os(tvOS)
                focusButton(labelled: "TV Guide")
                XCUIRemote.shared.press(.select)
            #else
                app.buttons["TV Guide"].tap()
            #endif
            // Waits for the grid to draw; on Apple TV its cells are not always in the tree, so this does not fail the
            // scene.
            _ = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Morning Report,'")).firstMatch
                .waitForExistence(timeout: 20)
            capture("03-guide")
        }
    #endif
}

final class StoreMoviesScene: StoreScene {
    override var startTab: String {
        "movies"
    }

    func testMovies() {
        _ = app.buttons["Sintel"].waitForExistence(timeout: 30)
        capture("04-movies")
    }

    /// The grid of posters, with their ratings, below the hero.
    func testMovieGrid() {
        _ = app.buttons["Sintel"].waitForExistence(timeout: 30)
        #if os(tvOS)
            for _ in 0 ..< 4 {
                XCUIRemote.shared.press(.down)
            }
        #else
            app.swipeUp(velocity: .slow)
            app.swipeUp(velocity: .slow)
        #endif
        capture("06-movie-grid")
    }
}
