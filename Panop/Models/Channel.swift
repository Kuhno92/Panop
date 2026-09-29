import Foundation
import PanopCore
import SwiftData

/// A live channel or VOD item in the local catalogue.
///
/// Lives in the **catalog** container, which is local-only. That is what lets
/// it use `@Attribute(.unique)` and real relationships, both of which CloudKit
/// mirroring forbids. See docs/adr/0003-two-model-containers.md.
@Model
final class Channel {
    @Attribute(.unique) var id: String
    var name: String
    var streamURL: String
    var tvgID: String?
    var logoURL: String?
    var groupTitle: String?
    var kindRaw: String
    var sortIndex: Int

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .unknown }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: String,
        name: String,
        streamURL: String,
        tvgID: String? = nil,
        logoURL: String? = nil,
        groupTitle: String? = nil,
        kind: MediaKind = .unknown,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.tvgID = tvgID
        self.logoURL = logoURL
        self.groupTitle = groupTitle
        kindRaw = kind.rawValue
        self.sortIndex = sortIndex
    }
}

extension Channel {
    /// Builds a model from a parsed playlist entry.
    ///
    /// The mapping lives here rather than in PanopKit because `PlaylistEntry`
    /// must stay free of SwiftData for the core to remain portable.
    convenience init(entry: PlaylistEntry, playlistID: String, sortIndex: Int) {
        self.init(
            id: "\(playlistID)|\(entry.url)",
            name: entry.name,
            streamURL: entry.url,
            tvgID: entry.attributes.tvgID,
            logoURL: entry.attributes.tvgLogo,
            groupTitle: entry.attributes.groupTitle,
            kind: entry.mediaKind,
            sortIndex: sortIndex
        )
    }
}
