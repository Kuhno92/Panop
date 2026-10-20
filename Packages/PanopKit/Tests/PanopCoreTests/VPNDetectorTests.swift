@testable import PanopCore
import Testing

struct VPNDetectorTests {
    @Test(arguments: ["utun3", "ipsec0", "ppp0", "tun0", "tap0", "UTUN1"])
    func `a VPN interface is recognised`(name: String) {
        #expect(VPNDetector.isVPNInterface(name))
    }

    @Test(arguments: ["en0", "en1", "lo0", "pdp_ip0", "awdl0", "bridge100", ""])
    func `an ordinary interface is not`(name: String) {
        #expect(!VPNDetector.isVPNInterface(name))
    }

    @Test func `a VPN among other interfaces counts`() {
        #expect(VPNDetector.isActive(interfaces: ["en0", "lo0", "utun4"]))
        #expect(!VPNDetector.isActive(interfaces: ["en0", "lo0"]))
        #expect(!VPNDetector.isActive(interfaces: []))
    }

    @Test func `traffic is held only when a VPN is wanted and absent`() {
        #expect(VPNDetector.block(requireVPN: true, interfaces: ["en0"]) == .vpnRequired)
        #expect(VPNDetector.block(requireVPN: true, interfaces: ["en0", "utun2"]) == nil)
        #expect(VPNDetector.block(requireVPN: false, interfaces: ["en0"]) == nil)
    }
}
