import Foundation
import Observation
import Security

/// Whether the person's own data (favourites, what they watched, hidden titles, category choices, their
/// playlists) is mirrored to their iCloud, and why not when it is not.
///
/// Mirroring is only asked of SwiftData when every condition holds. Asking without the iCloud entitlement
/// does not degrade: the app fails to open its store. So the choice is made here, from facts, and a
/// container that still fails to open falls back to a local one instead of ending the app.
nonisolated enum CloudSync {
    /// Named after the bundle identifier, as Apple's own apps do.
    static let containerID = "iCloud.com.panop.Panop"
    /// The Settings switch. On by default: the data is the person's own, in their own iCloud.
    static let enabledKey = "iCloudSync"
    /// Whether provider logins travel with the playlists, encrypted. On by default, since a playlist
    /// that arrives on another device without its login cannot be used there.
    static let loginsKey = "iCloudSyncLogins"

    enum Availability: Equatable, Sendable {
        /// Mirroring is on.
        case active
        /// The person turned it off.
        case off
        /// No iCloud account is signed in on this device.
        case noAccount
        /// This build has no iCloud entitlement, such as an ad hoc build or a test run.
        case notEntitled
        /// A test, which never touches the person's iCloud.
        case testing
        /// It was asked for and the store would not open with it, so the local one is in use.
        case failed(String)
    }

    /// The decision, from facts alone.
    static func decide(isOn: Bool, hasAccount: Bool, isEntitled: Bool, underTest: Bool) -> Availability {
        if underTest {
            return .testing
        }
        if !isOn {
            return .off
        }
        if !isEntitled {
            return .notEntitled
        }
        return hasAccount ? .active : .noAccount
    }

    /// The decision now, from what this process has and what the person set.
    static func current(underTest: Bool, defaults: UserDefaults = .standard) -> Availability {
        decide(
            isOn: defaults.object(forKey: enabledKey) as? Bool ?? true,
            hasAccount: FileManager.default.ubiquityIdentityToken != nil,
            isEntitled: hasEntitlement,
            underTest: underTest
        )
    }

    /// Whether this build carries the iCloud entitlement. On a Mac the process's own entitlements can be
    /// read; elsewhere there is no public way, so an account that iCloud answers for stands in: iCloud
    /// gives no identity to an app without the capability.
    static var hasEntitlement: Bool {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                  let services = SecTaskCopyValueForEntitlement(
                      task, "com.apple.developer.icloud-services" as CFString, nil
                  ) as? [String]
            else { return false }
            return services.contains("CloudKit")
        #else
            return FileManager.default.ubiquityIdentityToken != nil
        #endif
    }

    /// Whether the logins are to travel with the playlists.
    static func syncsLogins(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: loginsKey) as? Bool ?? true
    }
}

/// What the Settings screen says about iCloud: set once, when the stores were opened.
@MainActor
@Observable
final class CloudSyncStatus {
    private(set) var availability: CloudSync.Availability

    init(_ availability: CloudSync.Availability = .off) {
        self.availability = availability
    }

    func update(_ availability: CloudSync.Availability) {
        self.availability = availability
    }
}
