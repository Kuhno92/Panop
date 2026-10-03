import CryptoKit
import Foundation

/// How a playlist's login travels between the person's devices.
///
/// The login (an address, a username, a password) lives in each device's Keychain. To reach another device
/// it is also written to an encrypted field of the playlist's record, which CloudKit encrypts end to end
/// with a key that is itself kept in iCloud Keychain. Whether it is written at all is the person's choice.
///
/// This is only the decision, from facts, so every case is testable without iCloud.
nonisolated enum PlaylistLogins {
    enum Action: Equatable {
        case none
        /// Write this to the record, so other devices have it.
        case upload(Data)
        /// Another device's login is the one to use: put it in this device's Keychain.
        case adopt(PlaylistSecret)
        /// The person turned logins off: take it out of the record.
        case withdraw
    }

    static func encode(_ secret: PlaylistSecret) -> Data? {
        try? JSONEncoder().encode(secret)
    }

    static func decode(_ data: Data) -> PlaylistSecret? {
        try? JSONDecoder().decode(PlaylistSecret.self, from: data)
    }

    /// What identifies a blob without keeping it: remembered per playlist, in plain preferences, where a
    /// password must not be.
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// - Parameters:
    ///   - local: this device's login, if it has one.
    ///   - blob: the login on the record, if one is there.
    ///   - remembered: the digest of the blob this device last wrote or took, if it ever has.
    ///   - uploading: whether the person wants logins to travel.
    static func decide(local: PlaylistSecret?, blob: Data?, remembered: String?, uploading: Bool) -> Action {
        guard uploading else {
            return blob == nil ? .none : .withdraw
        }
        let mine = local.flatMap(encode)
        switch (mine, blob) {
        case (nil, nil):
            return .none
        case let (mine?, nil):
            return .upload(mine)
        case let (nil, blob?):
            return decode(blob).map(Action.adopt) ?? .none
        case let (mine?, blob?):
            if mine == blob {
                return .none
            }
            // They differ. If the record is still what this device last put there, the change is this
            // device's: send it. Otherwise another device changed it since, and that one stands.
            if remembered == digest(blob) {
                return .upload(mine)
            }
            return decode(blob).map(Action.adopt) ?? .upload(mine)
        }
    }
}
