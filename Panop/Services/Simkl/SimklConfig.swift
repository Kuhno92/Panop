import Foundation
import PanopCore
import PanopSimkl

/// How this build identifies itself to Simkl.
nonisolated enum SimklConfig {
    /// The public id of Panop's registration at https://simkl.com/settings/developer/. Empty until the app
    /// is registered, and while it is empty nothing is asked of Simkl and no Simkl rail or login is offered.
    static let clientID = "e7fc78a9f51d1011e6a0a9507550de40def4dbb49b9db8ab932cf7070b12bf78"

    /// The Keychain, except under tests: a test host is signed differently from the app the person
    /// connected with, so touching the real item makes macOS ask for a password and hangs the run.
    @MainActor
    static var tokenStore: any SimklTokenStore {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return testing || UITestMode.isActive ? InMemorySimklTokenStore() : KeychainSimklTokenStore()
    }

    static var isConfigured: Bool {
        !clientID.isEmpty
    }

    static var app: SimklApp {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return SimklApp(clientID: clientID, version: version)
    }
}

extension SimklTrendingSource {
    /// The source as the app uses it, or nil while the app has no Simkl registration.
    static var panop: SimklTrendingSource? {
        SimklConfig.isConfigured ? SimklTrendingSource(transport: URLSessionTransport(), app: SimklConfig.app) : nil
    }
}
