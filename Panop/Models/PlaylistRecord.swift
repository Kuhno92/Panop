import Foundation
import SwiftData

/// A playlist the user added. Lives in the **cloud** container, so it follows
/// the CloudKit rules: every property optional or defaulted, no
/// `@Attribute(.unique)`, no relationships. Breaking one fails at runtime when
/// mirroring starts, not at compile time. See docs/adr/0003-two-model-containers.md.
///
/// Holds only what is safe to sync. Anything that can be used to fetch the
/// playlist (URLs, usernames, passwords) is in the Keychain, keyed by `id`.
/// `id` is also the playlist identifier every catalog row is stamped with.
@Model
final class PlaylistRecord {
    var id: String = ""
    var name: String = ""
    var kindRaw: String = PlaylistKind.xtream.rawValue
    /// The host, for display. Never the full URL, which may embed credentials.
    var displayHost: String = ""
    /// File name of the app's own copy of a local M3U, inside the playlists directory.
    var localFileName: String?
    var createdAt: Date = Date.distantPast
    var sortOrder: Int = 0

    init(
        id: String,
        name: String,
        kind: PlaylistKind,
        displayHost: String,
        localFileName: String? = nil,
        createdAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        kindRaw = kind.rawValue
        self.displayHost = displayHost
        self.localFileName = localFileName
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    var kind: PlaylistKind {
        PlaylistKind(rawValue: kindRaw) ?? .xtream
    }
}

nonisolated enum PlaylistKind: String, Sendable, CaseIterable {
    case remoteM3U
    case localM3U
    case xtream
}

/// A playlist as the UI sees it: a plain value, so views never hold a live model
/// object from the cloud container.
nonisolated struct PlaylistSummary: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: PlaylistKind
    var displayHost: String
    var createdAt: Date
}
