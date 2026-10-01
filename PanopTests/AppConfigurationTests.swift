import Foundation
@testable import Panop
import Testing

/// Settings that live in the project, not in code, and break the app in ways no unit
/// test of the code would notice.
@Suite("App configuration")
struct AppConfigurationTests {
    /// Without this, iOS, tvOS and macOS all refuse a plain `http://` request to a
    /// hostname with error -1022, which is how many IPTV providers serve playlists, Xtream
    /// APIs and streams. Found by fetching one from the app and watching it fail.
    @Test
    func `the app may load plain http, as IPTV providers need`() {
        let settings = Bundle(for: AppServices.self).object(forInfoDictionaryKey: "NSAppTransportSecurity")
        let ats = settings as? [String: Any]
        #expect(ats?["NSAllowsArbitraryLoads"] as? Bool == true)
    }

    #if os(iOS)
        @Test
        func `the app may keep playing audio in the background`() {
            let modes = Bundle(for: AppServices.self).object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
            #expect(modes?.contains("audio") == true)
        }
    #endif
}
