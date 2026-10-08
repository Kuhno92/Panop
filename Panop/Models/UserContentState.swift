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
    /// How long the stream is, as last seen, so progress can be shown and "finished" decided.
    /// Zero when unknown.
    var durationSeconds: Double = 0
    var updatedAt: Date = Date.distantPast
    /// When it was last opened, or `distantPast` if never. Defaulted, so a store made before
    /// this existed still opens.
    var lastPlayedAt: Date = Date.distantPast
    /// The engine that played this when the person's own choice could not, as its raw value, or
    /// empty. Defaulted, so a store made before this existed still opens.
    var rememberedEngine: String = ""
    /// For a channel's guide key (the row is filed under `guide:<key>`): the entry id of the version of that channel
    /// the
    /// person chose to play, or empty. Defaulted, so a store made before this existed still opens.
    var preferredVariantID: String = ""
    /// Seen to the end, or marked so. Defaulted, so a store made before this existed still opens.
    var isWatched: Bool = false
    /// Hidden by the person from every list, for an entry that is no use to them, such as a
    /// divider a provider put in its channel list. Defaulted, so an older store still opens.
    var isHidden: Bool = false
    /// How many times it has been opened. Defaulted, so an older store still opens.
    var playCount: Int = 0
    /// For an episode, the key of the series it belongs to, so what is watched can be told by show
    /// and not by episode. Empty for everything else.
    var parentKey: String = ""
    /// Which person's this is (see `ProfileStore`). Empty is the first profile, which is also what a
    /// store made before profiles existed holds, so nothing needs moving. Defaulted, so an older store opens.
    var profile: String = ""

    init(
        streamID: String = "",
        isFavorite: Bool = false,
        positionSeconds: Double = 0,
        durationSeconds: Double = 0,
        updatedAt: Date = .now,
        lastPlayedAt: Date = .distantPast
    ) {
        self.streamID = streamID
        self.isFavorite = isFavorite
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
        self.lastPlayedAt = lastPlayedAt
    }
}
