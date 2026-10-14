import Foundation
import SwiftUI

/// How the sports hub is set up in this build and on this device.
nonisolated enum SportsConfig {
    /// The Settings switch: whether the sportapi.ai key travels to the person's other devices through iCloud. On by
    /// default, as for the playlists' logins: a key that did not arrive means typing it again on every device, and
    /// typing a long key on an Apple TV is no pleasure.
    static let syncsKeyKey = "iCloudSyncSportsKey"

    static func syncsKey(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: syncsKeyKey) as? Bool ?? true
    }

    /// The Keychain, except under tests, which must never touch the person's own.
    @MainActor
    static var keyStore: any SportsKeyStore {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return testing || UITestMode.isActive ? InMemorySportsKeyStore() : KeychainSportsKeyStore()
    }

    /// A folder of its own under tests, so a run reads nothing left by another and leaves nothing behind.
    @MainActor
    static var cacheDirectory: URL {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if testing || UITestMode.isActive {
            return FileManager.default.temporaryDirectory.appendingPathComponent(
                "sports-\(UUID().uuidString)",
                isDirectory: true
            )
        }
        return SportsCacheStore.defaultDirectory
    }

    /// Where the service's own pages are.
    static let website = URL(string: "https://sportapi.ai/") ?? URL(filePath: "/")
}

extension EnvironmentValues {
    @Entry var sportsFeed: SportsFeed?
}
