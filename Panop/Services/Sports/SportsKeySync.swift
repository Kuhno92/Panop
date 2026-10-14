import Foundation

/// Whether the sportapi.ai key travels to the person's other devices, and which way: the decision, from facts alone,
/// so every case is testable without iCloud. It is `PlaylistLogins.decide` for one key, with one addition.
///
/// The key is in the Keychain of each device, which is where a device reads it from. The record (an encrypted field in
/// the person's own iCloud) only carries it between devices.
nonisolated enum SportsKeySync {
    enum Action: Equatable {
        case none
        /// Write this to the record, so other devices have it.
        case upload(Data)
        /// Another device's key is the one to use: put it in this device's Keychain.
        case adopt(String)
        /// The person took the key out on another device: take it out here too.
        case removeLocal
        /// The person turned the sync off: take it out of the record.
        case withdraw
    }

    static func encode(_ key: String) -> Data? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Data(trimmed.utf8)
    }

    static func decode(_ data: Data) -> String? {
        guard let text = String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    /// What identifies a blob without keeping it: remembered in plain preferences, where the key must not be.
    static func digest(_ data: Data) -> String {
        PlaylistLogins.digest(data)
    }

    /// - Parameters:
    ///   - local: this device's key, if it has one.
    ///   - blob: the key on the record, if one is there.
    ///   - removed: whether the record says the person took the key out.
    ///   - remembered: the digest of the blob this device last wrote or took, if it ever has.
    ///   - uploading: whether the person wants the key to travel.
    static func decide(local: String?, blob: Data?, removed: Bool, remembered: String?, uploading: Bool) -> Action {
        guard uploading else {
            return blob == nil ? .none : .withdraw
        }
        let mine = local.flatMap(encode)
        switch (mine, blob) {
        case (nil, nil):
            return .none
        case let (mine?, nil):
            // The record has none. If it says the key was taken out, and this device's key is the one that came from
            // the record, that removal is news here. A key the person typed in afterwards is a new one, and is sent.
            if removed, remembered == digest(mine) {
                return .removeLocal
            }
            return .upload(mine)
        case let (nil, blob?):
            return decode(blob).map(Action.adopt) ?? .none
        case let (mine?, blob?):
            if mine == blob {
                return .none
            }
            // They differ. If the record is still what this device last put there, the change is this device's:
            // send it. Otherwise another device changed it since, and that one stands.
            if remembered == digest(blob) {
                return .upload(mine)
            }
            return decode(blob).map(Action.adopt) ?? .upload(mine)
        }
    }
}
