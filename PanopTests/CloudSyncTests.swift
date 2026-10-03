import Foundation
@testable import Panop
import SwiftData
import Testing

@Suite("iCloud sync decision")
struct CloudSyncTests {
    @Test
    func `mirroring is on only when it is switched on, entitled and signed in`() {
        #expect(CloudSync.decide(isOn: true, hasAccount: true, isEntitled: true, underTest: false) == .active)
        #expect(CloudSync.decide(isOn: false, hasAccount: true, isEntitled: true, underTest: false) == .off)
        #expect(CloudSync.decide(isOn: true, hasAccount: false, isEntitled: true, underTest: false) == .noAccount)
        #expect(CloudSync.decide(isOn: true, hasAccount: true, isEntitled: false, underTest: false) == .notEntitled)
    }

    @Test
    func `a test never touches iCloud, whatever else is true`() {
        #expect(CloudSync.decide(isOn: true, hasAccount: true, isEntitled: true, underTest: true) == .testing)
    }

    @Test
    func `without the entitlement the reason given is the missing entitlement, not a missing account`() {
        // A build that cannot use iCloud should say so, rather than ask the person to sign in.
        #expect(CloudSync.decide(isOn: true, hasAccount: false, isEntitled: false, underTest: false) == .notEntitled)
    }

    @Test
    func `the switch is on and logins travel by default`() {
        let name = "panop-cloud-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(CloudSync.current(underTest: false, defaults: defaults) != .off)
        #expect(CloudSync.syncsLogins(defaults: defaults))

        defaults.set(false, forKey: CloudSync.enabledKey)
        defaults.set(false, forKey: CloudSync.loginsKey)
        #expect(CloudSync.current(underTest: false, defaults: defaults) == .off)
        #expect(!CloudSync.syncsLogins(defaults: defaults))
    }

    @Test
    func `an in-memory store is local even when mirroring was decided`() throws {
        let opened = try PanopContainers.openCloud(inMemory: true, availability: .active)

        #expect(opened.container.configurations.first?.isStoredInMemoryOnly == true)
    }

    @Test
    func `a store that is not to be mirrored opens locally and keeps the reason`() throws {
        let opened = try PanopContainers.openCloud(inMemory: true, availability: .noAccount)

        #expect(opened.availability == .noAccount)
    }
}

/// Against the real thing: opens the user-state store mirrored to the person's iCloud, which proves the
/// schema is accepted by CloudKit and the entitlement and container are in place. It touches the iCloud
/// account of whoever runs it (the development schema), so it only runs when asked, from a signed build:
///
///     TEST_RUNNER_PANOP_TEST_CLOUDKIT=1, with signing on and `CODE_SIGN_ENTITLEMENTS` not overridden.
@Suite(
    "iCloud, for real",
    .enabled(if: ProcessInfo.processInfo.environment["PANOP_TEST_CLOUDKIT"] != nil)
)
struct CloudKitSmokeTests {
    @Test
    func `the user state opens mirrored to the iCloud container`() throws {
        try #require(CloudSync.hasEntitlement, "this build has no iCloud entitlement: it is not signed for it")

        let container = try PanopContainers.makeCloud(mirrored: true)

        #expect(container.configurations.first?.cloudKitDatabase != nil)
    }
}
