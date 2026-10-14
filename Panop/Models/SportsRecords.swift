import Foundation
import SwiftData

/// One thing the person chose in the sports hub: a league, a favourite team, whether setup is done, a channel they
/// picked for a league. A single kind of row, so that a later setting needs no new schema.
///
/// In the cloud container, so it travels to the person's other devices (ADR 0009). The same rules as every record
/// there: each property has a default, nothing is unique, nothing is related to anything else. Two devices can
/// therefore each write the same choice, and a read keeps the newest (see `SportsSyncStore`).
@Model
final class SportsPreference {
    /// Which person chose this: empty is the first profile (see `UserContentState.profile`). Settings of the device
    /// as a whole, such as showing the Sports tab, use `SportsPreference.deviceWide`.
    var profile: String = ""
    var kind: String = ""
    var key: String = ""
    var value: String = ""
    var position: Int = 0
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// The profile name of what is not one person's.
    static let deviceWide = "*"

    init(
        profile: String = "",
        kind: String = "",
        key: String = "",
        value: String = "",
        position: Int = 0,
        at date: Date = .now
    ) {
        self.profile = profile
        self.kind = kind
        self.key = key
        self.value = value
        self.position = position
        updatedAt = date
    }
}

/// The sportapi.ai key, so a second device has it without typing it again.
///
/// The field is encrypted end to end by CloudKit, with a key kept in iCloud Keychain, the same way a playlist's login
/// is (`PlaylistRecord.encryptedLogin`). `removed` marks a key the person took out: without it, another device would
/// read the empty record as a key that has not arrived yet, and send its own back.
@Model
final class SportsKeyRecord {
    @Attribute(.allowsCloudEncryption) var encryptedKey: Data?
    var removed: Bool = false
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    init(encryptedKey: Data? = nil, removed: Bool = false, at date: Date = .now) {
        self.encryptedKey = encryptedKey
        self.removed = removed
        updatedAt = date
    }
}
