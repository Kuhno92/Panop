import Foundation
import SwiftData

/// Per-user state that follows the user between devices.
///
/// Lives in the **cloud** container, which mirrors to CloudKit. That imposes
/// rules this type must keep to: every property optional or defaulted, no
/// `@Attribute(.unique)`, and no relationships. Breaking any of them fails at
/// runtime when mirroring initialises, not at compile time.
///
/// See docs/adr/0003-two-model-containers.md.
@Model
final class UserContentState {
    /// `UserStateStore.key(playlist:entry:)`: the playlist and the entry together. An entry's own
    /// id is not enough, because two Xtream providers can both have a stream 42.
    var streamID: String = ""
    var isFavorite: Bool = false
    /// Resume position in seconds.
    var positionSeconds: Double = 0
    var updatedAt: Date = Date.distantPast
    /// When it was last opened, or `distantPast` if never. Defaulted, so a store made before
    /// this existed still opens.
    var lastPlayedAt: Date = Date.distantPast

    init(
        streamID: String = "",
        isFavorite: Bool = false,
        positionSeconds: Double = 0,
        updatedAt: Date = .now,
        lastPlayedAt: Date = .distantPast
    ) {
        self.streamID = streamID
        self.isFavorite = isFavorite
        self.positionSeconds = positionSeconds
        self.updatedAt = updatedAt
        self.lastPlayedAt = lastPlayedAt
    }
}
