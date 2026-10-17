import XCTest

/// How the screens feel with a big catalog (a playlist of 30,000 channels, 10,000 films and 10,000 episodes the
/// developer generates into /tmp/perf/mid.m3u, never committed). Times are written to /tmp/perf/times.txt, for the
/// developer to read: a UI test's clock includes the test's own overhead, so they are for comparing a change with the
/// one before it, not for absolute claims. Skipped without the file.
final class PerformanceTests: PanopUITestCase {
    private static let file = "/tmp/perf/mid.m3u"

    override var seedFile: String? {
        FileManager.default.fileExists(atPath: Self.file) ? Self.file : nil
    }

    override var startTab: String {
        "home"
    }

    private let started = Date()

    private func log(_ what: String, since: Date? = nil) {
        let seconds = Date().timeIntervalSince(since ?? started)
        let line = String(format: "%@ %.2f s\n", what, seconds)
        let url = URL(fileURLWithPath: "/tmp/perf/times.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    #if os(tvOS)
        private func goToTab(_ name: String) {
            let button = app.tabBars.buttons[name]
            for _ in 0 ..< 6 where !button.hasFocus {
                XCUIRemote.shared.press(.up)
            }
            for _ in 0 ..< 8 where !button.hasFocus {
                XCUIRemote.shared.press(.right)
            }
            for _ in 0 ..< 8 where !button.hasFocus {
                XCUIRemote.shared.press(.left)
            }
            XCUIRemote.shared.press(.select)
        }

        func testHomeTabsAndTheWayBackFromAStream() throws {
            try XCTSkipIf(seedFile == nil, "no /tmp/perf/mid.m3u")
            try? FileManager.default.removeItem(atPath: "/tmp/perf/times.txt")
            // Home is ready when it has said what it has: a hero or the way to the channels, or that there is nothing
            // yet.
            let ready = app.buttons.matching(NSPredicate(
                format: "label IN {'Browse all channels', 'Browse Live TV', 'Play'}"
            )).firstMatch
            XCTAssertTrue(
                ready.waitForExistence(timeout: 240),
                "Home never became ready. Screen:\n\(app.debugDescription)"
            )
            log("home ready (launch, import and first screen)")
            // Idle, so what runs in the background after the first screen is in the profile too.
            Thread.sleep(forTimeInterval: 10)

            for name in ["Live TV", "Movies", "Series", "Home"] {
                let began = Date()
                goToTab(name)
                // Something of the screen that is new.
                let marker: XCUIElement = switch name {
                case "Live TV": app.cells.firstMatch
                case "Movies",
                     "Series": app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Suggestions'")).firstMatch
                default: app.buttons
                    .matching(NSPredicate(format: "label IN {'Browse all channels', 'Browse Live TV', 'Play'}"))
                    .firstMatch
                }
                _ = marker.waitForExistence(timeout: 60)
                log("tab \(name) shown", since: began)
                Thread.sleep(forTimeInterval: 3)
            }

            goToTab("Live TV")
            XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 60))
            Thread.sleep(forTimeInterval: 2)
            for _ in 0 ..< 6 {
                XCUIRemote.shared.press(.down)
            }
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 60), "no stream")
            Thread.sleep(forTimeInterval: 4)
            let back = Date()
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.buttons["Show stream"].waitForExistence(timeout: 60), "the app did not come back")
            log("back from the stream: panel shown", since: back)
            Thread.sleep(forTimeInterval: 3)
            XCUIRemote.shared.press(.right)
            log("after one more press", since: back)
        }
    #endif
}
