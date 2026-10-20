import PanopTunnel
import XCTest

/// Runs the Go tunnel's end-to-end self-test (a stand-in VPN server and the real client, in this process) on
/// whichever platform this test runs on. Needs the framework built with `Scripts/build-tunnel.sh --selftest`.
final class TunnelSelfTests: XCTestCase {
    func testWireGuardPathWorksOnThisPlatform() {
        XCTAssertEqual(TunnelSelfTest(), "")
    }

    func testStartRefusesAConfigurationWithoutAKey() throws {
        let tunnel = try XCTUnwrap(TunnelNewTunnel())
        XCTAssertThrowsError(try tunnel.start("[Interface]\nAddress = 10.0.0.2/32\n"))
        XCTAssertEqual(tunnel.socksPort(), 0)
    }

    func testAnErrorNamesTheLineButNotTheKey() throws {
        let tunnel = try XCTUnwrap(TunnelNewTunnel())
        XCTAssertThrowsError(try tunnel.start("[Interface]\nPrivateKey = not-a-key-SECRETVALUE\n")) { error in
            XCTAssertFalse(error.localizedDescription.contains("SECRETVALUE"))
            XCTAssertTrue(error.localizedDescription.contains("line 2"))
        }
    }
}
