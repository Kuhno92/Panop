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

    /// The tab the app opens on: Live TV, since most tests are about it.
    /// Gives Home a hero title, which the seeded library has no suggestions to choose from.
    var showsHero: Bool {
        false
    }

    var startTab: String {
        "live"
    }

    /// A language code to run the app in, such as `de`, or nil for the simulator's own.
    var launchLanguage: String? {
        nil
    }

    /// Seed the playlist as a live-only source, which hides the Movies and Series tabs.
    var liveOnly: Bool {
        false
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
        if let language = launchLanguage {
            app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        }
        app.launchEnvironment["PANOP_CONTROLS_TIMEOUT"] = String(controlsTimeout)
        app.launchEnvironment["PANOP_START_TAB"] = startTab
        if showsHero {
            app.launchEnvironment["PANOP_HERO"] = "1"
        }
        if liveOnly {
            app.launchEnvironment["PANOP_LIVE_ONLY"] = "1"
        }
        app.launch()
    }

    /// The list is alphabetical and lazy, so only the first rows exist on screen: `3sat`, then
    /// `Arte`. Tests that need a row look for those.
    ///
    /// A channel row, found by name. A row's label also carries its group.
    func channel(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    #if !os(tvOS)
        /// Opens Settings: its tab where there is one, and on a phone the button on Home, which has no room for the
        /// tab.
        func openSettings(named name: String = "Settings") {
            let tab = app.tabBars.buttons[name]
            if tab.exists {
                tab.tap()
            } else {
                app.tabBars.buttons.element(boundBy: 0).tap()
                app.buttons[name].tap()
            }
        }
    #endif

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
        /// Focus starts on the tab bar. Down from there reaches the search magnifier, then the TV Guide
        /// button, the Show filter, the Sort row, the category chips, then the first channel. Pressed until the
        /// channel has focus, not counted, so a row added above it does not break every test that follows.
        func focusFirstChannel() {
            focus(channel("Das Erste"))
        }

        /// Moves down until one of the buttons with this label has focus, for a label the tree holds more than once.
        func focusButton(labelled label: String) {
            // In a list the focused thing can be the row (a cell) that holds the button, not the button.
            let matches = app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@ AND (elementType == %d OR elementType == %d)",
                label,
                XCUIElement.ElementType.button.rawValue,
                XCUIElement.ElementType.cell.rawValue
            ))
            for _ in 0 ..< 12 where !matches.allElementsBoundByIndex.contains(where: \.hasFocus) {
                XCUIRemote.shared.press(.down)
            }
        }

        /// Moves down until `element` has focus, up to a dozen presses.
        func focus(_ element: XCUIElement) {
            for _ in 0 ..< 12 where !(element.exists && element.hasFocus) {
                XCUIRemote.shared.press(.down)
            }
        }
    #endif
}
