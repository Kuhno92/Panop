import Foundation
import SwiftData

/// The WireGuard configuration the person added, so another of their devices (an Apple TV, which has no way to
/// paste a file) has it without being typed in again.
///
/// The field is encrypted end to end by CloudKit, with a key kept in iCloud Keychain, like a playlist's login
/// (`PlaylistRecord.encryptedLogin`) and the sportapi.ai key (`SportsKeyRecord`). `removed` marks a configuration the
/// person took out: without it another device would read the empty record as one that has not arrived yet, and send
/// its own back. Whether a device *uses* the tunnel is that device's own switch and is not synced.
@Model
final class VPNConfigRecord {
    @Attribute(.allowsCloudEncryption) var encryptedConfig: Data?
    var removed: Bool = false
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    init(encryptedConfig: Data? = nil, removed: Bool = false, at date: Date = .now) {
        self.encryptedConfig = encryptedConfig
        self.removed = removed
        updatedAt = date
    }
}
