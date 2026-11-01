import CloudKit
import Foundation
import PanopCore

/// What clearing the synced data does in iCloud, decided from how this device uses it.
nonisolated enum ICloudWipeRoute: Equatable {
    /// This device mirrors: the rows deleted here are exported, and the other devices apply them. Nothing more to do.
    case mirrored
    /// This device does not mirror but the build may use iCloud: the data in iCloud is deleted directly.
    case wipe
    /// There is no iCloud to speak of here (no account, no entitlement, a test): only this device is cleared.
    case unavailable

    static func route(for availability: CloudSync.Availability) -> ICloudWipeRoute {
        switch availability {
        case .active: .mirrored
        // Switched off, or asked for and the mirrored store would not open: the entitlement is there, so what
        // another device left in iCloud can still be wiped.
        case .off, .failed: .wipe
        case .noAccount, .notEntitled, .testing: .unavailable
        }
    }
}

/// The zones SwiftData's CloudKit mirroring keeps its records in, told apart from anything else in the database.
nonisolated enum CloudZones {
    /// Core Data (and so SwiftData) mirrors into `com.apple.coredata.cloudkit.zone`. Matched by prefix, so a
    /// suffix a later system adds does not leave data behind.
    static let mirrorPrefix = "com.apple.coredata.cloudkit.zone"

    static func isMirror(_ name: String) -> Bool {
        name.hasPrefix(mirrorPrefix)
    }
}

nonisolated enum CloudWipeError: Error, LocalizedError, Equatable {
    case noAccount
    case unreachable

    var errorDescription: String? {
        switch self {
        case .noAccount: String(localized: "No iCloud account is signed in on this device.")
        case .unreachable: String(localized: "iCloud could not be reached. Try again with a connection.")
        }
    }
}

/// Deletes the person's synced data in iCloud itself. A protocol, so what the reset does can be tested without
/// CloudKit.
nonisolated protocol CloudDataWiper: Sendable {
    /// - Returns: how many zones were deleted.
    func wipe() async throws -> Int
}

nonisolated struct CloudKitDataWiper: CloudDataWiper {
    func wipe() async throws -> Int {
        let container = CKContainer(identifier: CloudSync.containerID)
        do {
            guard try await container.accountStatus() == .available else { throw CloudWipeError.noAccount }
            let database = container.privateCloudDatabase
            let zones = try await database.allRecordZones().map(\.zoneID).filter { CloudZones.isMirror($0.zoneName) }
            for zone in zones {
                try await database.deleteRecordZone(withID: zone)
            }
            return zones.count
        } catch let error as CloudWipeError {
            throw error
        } catch {
            throw CloudWipeError.unreachable
        }
    }
}

/// What a reset did, for Settings to say.
struct SyncedDataResetResult: Equatable {
    enum ICloud: Equatable {
        /// Sync is on: the cleared state goes to iCloud and the other devices by the sync itself.
        case carriedBySync
        case wiped(zones: Int)
        /// No iCloud to wipe on this device.
        case nothingToWipe
        case failed(String)
    }

    var iCloud: ICloud
    /// Playlists that could not be deleted, by name, so they are still here.
    var playlistsKept: [String]

    var isComplete: Bool {
        if case .failed = iCloud {
            return false
        }
        return playlistsKept.isEmpty
    }
}

/// "Clear synced data": everything the app syncs, on this device and, as the person's iCloud setting says, in iCloud.
///
/// Locally it goes through the paths that already know how (a playlist is removed as the person would remove it).
/// A sports key and a VPN configuration are removed through their own methods, which leave the `removed` marker that
/// other devices obey: deleting their records instead would let another device send its own copy back.
/// What is kept: the profile list (not synced, and the person's), Simkl, and the settings switches.
@MainActor
final class SyncedDataReset {
    private let library: PlaylistLibrary
    private let userState: UserStateStore
    private let sportsSync: SportsSyncStore
    private let sportsAccount: SportsAccount
    private let tunnel: TunnelController
    private let wiper: any CloudDataWiper
    private let defaults: UserDefaults

    init(
        library: PlaylistLibrary,
        userState: UserStateStore,
        sportsSync: SportsSyncStore,
        sportsAccount: SportsAccount,
        tunnel: TunnelController = .shared,
        wiper: any CloudDataWiper = CloudKitDataWiper(),
        defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.userState = userState
        self.sportsSync = sportsSync
        self.sportsAccount = sportsAccount
        self.tunnel = tunnel
        self.wiper = wiper
        self.defaults = defaults
    }

    func run(availability: CloudSync.Availability) async -> SyncedDataResetResult {
        // Playlists first and through their own removal: the catalog goes before the record, as it does for the
        // person, and each playlist's login, file and state with it.
        var kept: [String] = []
        for playlist in library.playlists {
            let failure = await library.remove(playlist.id)
            if failure != nil {
                kept.append(playlist.name)
            }
        }
        userState.deleteEverything()
        sportsSync.deleteEverything()
        sportsAccount.removeKey()
        tunnel.removeConfiguration()
        // As on a first launch: playlists that arrive from iCloud later are offered, not fetched unasked.
        defaults.removeObject(forKey: PlaylistLibrary.offerDecidedKey)

        let iCloud: SyncedDataResetResult.ICloud
        switch ICloudWipeRoute.route(for: availability) {
        case .mirrored:
            iCloud = .carriedBySync
        case .unavailable:
            iCloud = .nothingToWipe
        case .wipe:
            do {
                iCloud = try await .wiped(zones: wiper.wipe())
            } catch let error as CloudWipeError where error == .noAccount {
                iCloud = .nothingToWipe
            } catch {
                iCloud = .failed(error.localizedDescription)
            }
        }
        return SyncedDataResetResult(iCloud: iCloud, playlistsKept: kept)
    }
}
