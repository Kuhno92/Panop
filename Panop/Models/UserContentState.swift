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
    var streamID: String = ""
    var isFavorite: Bool = false
    /// Resume position in seconds.
    var positionSeconds: Double = 0
    var updatedAt: Date = Date.distantPast

    init(
        streamID: String = "",
        isFavorite: Bool = false,
        positionSeconds: Double = 0,
        updatedAt: Date = .now
    ) {
        self.streamID = streamID
        self.isFavorite = isFavorite
        self.positionSeconds = positionSeconds
        self.updatedAt = updatedAt
    }
}
