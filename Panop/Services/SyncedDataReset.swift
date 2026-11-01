import CloudKit
import Foundation
import PanopCore
import SwiftData

/// What clearing the synced data does in iCloud, decided from how this device uses it.
nonisolated enum ICloudWipeRoute: Equatable {
    /// This device mirrors: iCloud is wiped and this device's data is written back, so it is what iCloud holds and
    /// what the other devices take over. Nothing on this device is cleared.
    case replace
    /// This device does not mirror but the build may use iCloud: the data in iCloud is deleted directly.
    case wipe
    /// There is no iCloud to speak of here (no account, no entitlement, a test): only this device is cleared.
    case unavailable

    static func route(for availability: CloudSync.Availability) -> ICloudWipeRoute {
        switch availability {
        case .active: .replace
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
        /// Sync is on: iCloud was wiped and holds this device's data now (it is written back by the sync).
        case replaced
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

/// "Clear synced data".
///
/// **Sync on: iCloud is replaced by this device.** This device's data is snapshotted, the data in iCloud is wiped, and
/// the
/// snapshot is written back as new rows, which the mirroring exports to the zone iCloud makes again. Nothing is cleared
/// on this device, so what is here is the new synced state and the other devices take it over. Mirroring may empty this
/// device when it sees the zone gone; the snapshot (also kept on disk until done) is then put back by natural key, so
/// that is safe whichever way it behaves. If the wipe fails nothing has been touched.
///
/// **Sync off, or no mirroring: everything is cleared.** Playlists go as the person would remove them, then the rest,
/// the
/// sports key and the VPN configuration through their own methods (they leave the `removed` marker other devices obey),
/// and the data in iCloud is wiped directly when the build can reach it.
///
/// What is kept either way: the profile list (not synced, and the person's), Simkl, and the settings switches.
@MainActor
final class SyncedDataReset {
    private let library: PlaylistLibrary
    private let userState: UserStateStore
    private let sportsSync: SportsSyncStore
    private let sportsAccount: SportsAccount
    private let tunnel: TunnelController
    private let cloud: ModelContainer
    private let wiper: any CloudDataWiper
    private let defaults: UserDefaults
    private let snapshotFile: URL
    private let settleDelay: Duration
    /// The write-back that runs a little after a replace, to see it through. Tests wait for it.
    private(set) var settling: Task<Void, Never>?

    init(
        library: PlaylistLibrary,
        userState: UserStateStore,
        sportsSync: SportsSyncStore,
        sportsAccount: SportsAccount,
        cloud: ModelContainer,
        tunnel: TunnelController = .shared,
        wiper: any CloudDataWiper = CloudKitDataWiper(),
        defaults: UserDefaults = .standard,
        snapshotFile: URL = SyncedSnapshot.file,
        settleDelay: Duration = .seconds(20)
    ) {
        self.library = library
        self.userState = userState
        self.sportsSync = sportsSync
        self.sportsAccount = sportsAccount
        self.cloud = cloud
        self.tunnel = tunnel
        self.wiper = wiper
        self.defaults = defaults
        self.snapshotFile = snapshotFile
        self.settleDelay = settleDelay
    }

    func run(availability: CloudSync.Availability) async -> SyncedDataResetResult {
        switch ICloudWipeRoute.route(for: availability) {
        case .replace:
            return await replaceICloud()
        case .unavailable:
            return await SyncedDataResetResult(iCloud: .nothingToWipe, playlistsKept: clearEverything())
        case .wipe:
            let kept = await clearEverything()
            do {
                return try await SyncedDataResetResult(iCloud: .wiped(zones: wiper.wipe()), playlistsKept: kept)
            } catch let error as CloudWipeError where error == .noAccount {
                return SyncedDataResetResult(iCloud: .nothingToWipe, playlistsKept: kept)
            } catch {
                return SyncedDataResetResult(iCloud: .failed(error.localizedDescription), playlistsKept: kept)
            }
        }
    }

    // MARK: - Sync on: iCloud takes this device's data

    private func replaceICloud() async -> SyncedDataResetResult {
        let context = ModelContext(cloud)
        let snapshot = SyncedSnapshot.capture(from: context)
        do {
            // Before anything is touched: a restore that cannot be saved is not started.
            try snapshot.save(to: snapshotFile)
            _ = try await wiper.wipe()
        } catch {
            SyncedSnapshot.discard(at: snapshotFile)
            return SyncedDataResetResult(iCloud: .failed(error.localizedDescription), playlistsKept: [])
        }
        snapshot.rewrite(in: context)
        refresh()
        settling = Task { [weak self, settleDelay, snapshotFile] in
            try? await Task.sleep(for: settleDelay)
            await self?.settle(snapshot, file: snapshotFile)
        }
        return SyncedDataResetResult(iCloud: .replaced, playlistsKept: [])
    }

    /// Puts back what mirroring emptied in the meantime, then lets go of the snapshot.
    private func settle(_ snapshot: SyncedSnapshot, file: URL) {
        snapshot.insertMissing(into: ModelContext(cloud))
        refresh()
        SyncedSnapshot.discard(at: file)
    }

    /// At launch: a replace that was interrupted (the app quit before it was seen through) is finished.
    static func finishInterrupted(
        cloud: ModelContainer,
        file: URL = SyncedSnapshot.file,
        delay: Duration = .seconds(20),
        refresh: @escaping @MainActor () -> Void
    ) {
        guard let snapshot = SyncedSnapshot.load(from: file) else { return }
        Task {
            // Mirroring's first import after a launch is what may empty the store; after it is the time to look.
            try? await Task.sleep(for: delay)
            snapshot.insertMissing(into: ModelContext(cloud))
            refresh()
            SyncedSnapshot.discard(at: file)
        }
    }

    private func refresh() {
        library.reload()
        userState.reloadAfterRemoteChange()
        sportsSync.reloadAfterRemoteChange()
    }

    // MARK: - Clearing

    /// Returns the playlists that could not be deleted, by name.
    private func clearEverything() async -> [String] {
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
        return kept
    }
}
