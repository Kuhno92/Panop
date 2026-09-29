import Foundation

public struct EPGChannel: Sendable, Equatable, Hashable {
    /// The XMLTV channel id. Playlists reference it as `tvg-id` or, for Xtream,
    /// `epg_channel_id`. Compare case-insensitively: providers disagree.
    public var id: String
    public var displayNames: [String]
    public var iconURL: String?

    public init(id: String, displayNames: [String] = [], iconURL: String? = nil) {
        self.id = id
        self.displayNames = displayNames
        self.iconURL = iconURL
    }
}

public struct EPGProgramme: Sendable, Equatable, Hashable {
    public var channelID: String
    public var start: Date
    /// Equal to `start` when the guide omits it, which XMLTV allows.
    public var stop: Date
    public var title: String
    public var subtitle: String?
    public var details: String?
    public var categories: [String]
    public var iconURL: String?
    /// Prefers the `onscreen` numbering system ("S02E05") when several exist.
    public var episodeNumber: String?
    /// The `lang` of the title that was kept.
    public var language: String?

    public init(
        channelID: String,
        start: Date,
        stop: Date,
        title: String,
        subtitle: String? = nil,
        details: String? = nil,
        categories: [String] = [],
        iconURL: String? = nil,
        episodeNumber: String? = nil,
        language: String? = nil
    ) {
        self.channelID = channelID
        self.start = start
        self.stop = stop
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.categories = categories
        self.iconURL = iconURL
        self.episodeNumber = episodeNumber
        self.language = language
    }
}

/// One parsed item, in document order.
///
/// A single stream rather than two lists so a guide is read in one pass.
/// Nearly every guide lists all channels first, but the format does not
/// promise it.
public enum EPGElement: Sendable, Equatable {
    case channel(EPGChannel)
    case programme(EPGProgramme)
}

/// Failures reading a guide. No case carries a URL: guide URLs for Xtream
/// panels embed the account's username and password.
public enum EPGError: Error, Equatable, Sendable {
    /// The document is not XMLTV, for example an HTML error page served with a
    /// 200 status.
    case notXMLTV
    case malformed
    /// The guide ended before `</tv>`. Anything that replaces stored listings
    /// with a guide must treat this as a failed import; a cut-off guide is
    /// indistinguishable from one for a shorter period.
    case truncated
    case corruptGzip
    case http(status: Int)
    /// The connection failed. Credentials are scrubbed from the message.
    case transport(message: String)
}
