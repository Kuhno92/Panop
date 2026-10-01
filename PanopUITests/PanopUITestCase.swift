import XCTest

/// Launches the app in its deterministic UI-test mode (`-panop-uitest`): in-memory storage, a
/// seeded playlist of thirty channels, and an engine that "plays" at once, so these tests
/// drive the real screens with no network.
@MainActor
class PanopUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// Seconds the player's controls stay up. Long, because a UI test is slower than the real
    /// four seconds; a test about the controls hiding overrides it.
    var controlsTimeout: Int {
        60
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Driving a Mac app needs an accessibility grant that is only given interactively.
        #if os(macOS)
            throw XCTSkip("UI tests run on the iOS and tvOS simulators.")
        #endif
        app = XCUIApplication()
        // The app clears its remembered filters when it starts in this mode. They are not set
        // here as launch arguments: those pin a value, and the app could then never change it.
        app.launchArguments = ["-panop-uitest"]
        app.launchEnvironment["PANOP_CONTROLS_TIMEOUT"] = String(controlsTimeout)
        app.launch()
    }

    /// The list is alphabetical and lazy, so only the first rows exist on screen: `3sat`, then
    /// `Arte`. Tests that need a row look for those.
    ///
    /// A channel row, found by name. A row's label also carries its group.
    func channel(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    func waitForChannels(file: StaticString = #filePath, line: UInt = #line) {
        let found = channel("3sat").waitForExistence(timeout: 30)
        // On a miss, what the screen held is the only clue to why.
        XCTAssertTrue(
            found,
            "the seeded playlist never appeared. Screen:\n\(app.debugDescription)",
            file: file,
            line: line
        )
    }

    #if os(tvOS)
        /// Focus starts on the tab bar. Down from there reaches the search keyboard, then the
        /// Show filter, then the first channel.
        func focusFirstChannel() {
            for _ in 0 ..< 3 {
                XCUIRemote.shared.press(.down)
            }
        }
    #endif
}
