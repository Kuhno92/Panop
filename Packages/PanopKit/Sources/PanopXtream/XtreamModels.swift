import Foundation

// The models decode the wire format directly and leniently (see
// LenientDecoding.swift). A row missing its identifier throws and is skipped by
// the streaming reader; every other field degrades to nil.

public struct XtreamCategory: Sendable, Equatable, Hashable, Decodable {
    public var id: String
    public var name: String
    public var parentID: String?

    public init(id: String, name: String, parentID: String? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }

    private enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name = "category_name"
        case parentID = "parent_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: [], debugDescription: "category_id"))
        }
        self.id = id
        name = container.lenientString(.name) ?? id
        // Panels send "0" for "no parent".
        parentID = container.lenientString(.parentID).flatMap { $0 == "0" ? nil : $0 }
    }
}

public struct XtreamLiveStream: Sendable, Equatable, Hashable, Decodable {
    public var streamID: Int
    public var name: String
    public var number: Int?
    public var iconURL: String?
    /// The XMLTV channel id, when the provider supplies one.
    public var epgChannelID: String?
    public var categoryID: String?
    public var added: Date?
    /// Whether the provider keeps a recording window for catch-up.
    public var hasArchive: Bool
    public var archiveDays: Int?
    /// A direct URL that replaces the panel's own stream path when present.
    public var directSource: String?

    public init(
        streamID: Int,
        name: String,
        number: Int? = nil,
        iconURL: String? = nil,
        epgChannelID: String? = nil,
        categoryID: String? = nil,
        added: Date? = nil,
        hasArchive: Bool = false,
        archiveDays: Int? = nil,
        directSource: String? = nil
    ) {
        self.streamID = streamID
        self.name = name
        self.number = number
        self.iconURL = iconURL
        self.epgChannelID = epgChannelID
        self.categoryID = categoryID
        self.added = added
        self.hasArchive = hasArchive
        self.archiveDays = archiveDays
        self.directSource = directSource
    }

    private enum CodingKeys: String, CodingKey {
        case streamID = "stream_id", name, number = "num", iconURL = "stream_icon"
        case epgChannelID = "epg_channel_id", categoryID = "category_id", added
        case hasArchive = "tv_archive", archiveDays = "tv_archive_duration", directSource = "direct_source"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let streamID = container.lenientInt(.streamID) else {
            throw DecodingError.keyNotFound(CodingKeys.streamID, .init(codingPath: [], debugDescription: "stream_id"))
        }
        self.streamID = streamID
        name = container.lenientString(.name) ?? ""
        number = container.lenientInt(.number)
        iconURL = container.lenientString(.iconURL)
        epgChannelID = container.lenientString(.epgChannelID)
        categoryID = container.lenientString(.categoryID)
        added = container.lenientDate(.added)
        hasArchive = container.lenientBool(.hasArchive) ?? false
        archiveDays = container.lenientInt(.archiveDays)
        directSource = container.lenientString(.directSource)
    }
}

public struct XtreamMovie: Sendable, Equatable, Hashable, Decodable {
    public var streamID: Int
    public var name: String
    public var number: Int?
    public var iconURL: String?
    public var rating: Double?
    public var categoryID: String?
    public var added: Date?
    /// File extension the stream is served as, such as `mkv`.
    public var containerExtension: String?
    public var directSource: String?

    public init(
        streamID: Int,
        name: String,
        number: Int? = nil,
        iconURL: String? = nil,
        rating: Double? = nil,
        categoryID: String? = nil,
        added: Date? = nil,
        containerExtension: String? = nil,
        directSource: String? = nil
    ) {
        self.streamID = streamID
        self.name = name
        self.number = number
        self.iconURL = iconURL
        self.rating = rating
        self.categoryID = categoryID
        self.added = added
        self.containerExtension = containerExtension
        self.directSource = directSource
    }

    private enum CodingKeys: String, CodingKey {
        case streamID = "stream_id", name, number = "num", iconURL = "stream_icon", rating
        case categoryID = "category_id", added, containerExtension = "container_extension"
        case directSource = "direct_source"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let streamID = container.lenientInt(.streamID) else {
            throw DecodingError.keyNotFound(CodingKeys.streamID, .init(codingPath: [], debugDescription: "stream_id"))
        }
        self.streamID = streamID
        name = container.lenientString(.name) ?? ""
        number = container.lenientInt(.number)
        iconURL = container.lenientString(.iconURL)
        rating = container.lenientDouble(.rating)
        categoryID = container.lenientString(.categoryID)
        added = container.lenientDate(.added)
        containerExtension = container.lenientString(.containerExtension)
        directSource = container.lenientString(.directSource)
    }
}

/// A series shell. Episodes are fetched on demand through
/// ``XtreamClient/seriesInfo(seriesID:)``, so listing series stays small.
public struct XtreamSeries: Sendable, Equatable, Hashable, Decodable {
    public var seriesID: Int
    public var name: String
    public var coverURL: String?
    public var plot: String?
    public var cast: String?
    public var director: String?
    public var genre: String?
    public var releaseDate: String?
    public var rating: Double?
    public var categoryID: String?
    public var lastModified: Date?
    public var backdropURLs: [String]

    public init(
        seriesID: Int,
        name: String,
        coverURL: String? = nil,
        plot: String? = nil,
        cast: String? = nil,
        director: String? = nil,
        genre: String? = nil,
        releaseDate: String? = nil,
        rating: Double? = nil,
        categoryID: String? = nil,
        lastModified: Date? = nil,
        backdropURLs: [String] = []
    ) {
        self.seriesID = seriesID
        self.name = name
        self.coverURL = coverURL
        self.plot = plot
        self.cast = cast
        self.director = director
        self.genre = genre
        self.releaseDate = releaseDate
        self.rating = rating
        self.categoryID = categoryID
        self.lastModified = lastModified
        self.backdropURLs = backdropURLs
    }

    private enum CodingKeys: String, CodingKey {
        case seriesID = "series_id", name, coverURL = "cover", plot, cast, director, genre
        case releaseDate, releaseDateSnake = "release_date", rating
        case categoryID = "category_id", lastModified = "last_modified", backdropURLs = "backdrop_path"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let seriesID = container.lenientInt(.seriesID) else {
            throw DecodingError.keyNotFound(CodingKeys.seriesID, .init(codingPath: [], debugDescription: "series_id"))
        }
        self.seriesID = seriesID
        name = container.lenientString(.name) ?? ""
        coverURL = container.lenientString(.coverURL)
        plot = container.lenientString(.plot)
        cast = container.lenientString(.cast)
        director = container.lenientString(.director)
        genre = container.lenientString(.genre)
        // Panels disagree on camelCase versus snake_case here.
        releaseDate = container.lenientString(.releaseDate) ?? container.lenientString(.releaseDateSnake)
        rating = container.lenientDouble(.rating)
        categoryID = container.lenientString(.categoryID)
        lastModified = container.lenientDate(.lastModified)
        backdropURLs = container.lenientStrings(.backdropURLs)
    }
}

public struct XtreamEpisode: Sendable, Equatable, Hashable, Decodable {
    /// Identifier used to build the stream URL. Unlike movies this is a string
    /// on some panels, so it is kept as one.
    public var id: String
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var title: String
    public var containerExtension: String?
    public var durationSeconds: Int?
    public var plot: String?
    public var imageURL: String?

    public init(
        id: String,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String,
        containerExtension: String? = nil,
        durationSeconds: Int? = nil,
        plot: String? = nil,
        imageURL: String? = nil
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.containerExtension = containerExtension
        self.durationSeconds = durationSeconds
        self.plot = plot
        self.imageURL = imageURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, season, episodeNumber = "episode_num", title
        case containerExtension = "container_extension", info
    }

    private enum InfoKeys: String, CodingKey {
        case durationSeconds = "duration_secs", plot, image = "movie_image"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: [], debugDescription: "id"))
        }
        self.id = id
        seasonNumber = container.lenientInt(.season) ?? 0
        episodeNumber = container.lenientInt(.episodeNumber) ?? 0
        title = container.lenientString(.title) ?? ""
        containerExtension = container.lenientString(.containerExtension)

        // `info` is `[]` rather than an object when the provider has nothing.
        if let info = try? container.nestedContainer(keyedBy: InfoKeys.self, forKey: .info) {
            durationSeconds = info.lenientInt(.durationSeconds)
            plot = info.lenientString(.plot)
            imageURL = info.lenientString(.image)
        }
    }
}

public struct XtreamSeriesInfo: Sendable, Equatable {
    public var name: String
    public var plot: String?
    public var coverURL: String?
    public var genre: String?
    public var episodes: [XtreamEpisode]

    public init(
        name: String,
        plot: String? = nil,
        coverURL: String? = nil,
        genre: String? = nil,
        episodes: [XtreamEpisode]
    ) {
        self.name = name
        self.plot = plot
        self.coverURL = coverURL
        self.genre = genre
        self.episodes = episodes
    }
}

extension XtreamSeriesInfo: Decodable {
    private enum CodingKeys: String, CodingKey { case info, episodes }
    private enum InfoKeys: String, CodingKey { case name, plot, cover, genre }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let info = try? container.nestedContainer(keyedBy: InfoKeys.self, forKey: .info) {
            name = info.lenientString(.name) ?? ""
            plot = info.lenientString(.plot)
            coverURL = info.lenientString(.cover)
            genre = info.lenientString(.genre)
        } else {
            name = ""
        }

        // Episodes are an object keyed by season number, or `[]` when empty.
        // Some panels send an array of season arrays instead.
        var all: [XtreamEpisode] = []
        if let bySeason = try? container.decodeIfPresent([String: [Lossy<XtreamEpisode>]].self, forKey: .episodes) {
            for (_, list) in bySeason {
                all += list.compactMap(\.value)
            }
        } else if let nested = try? container.decodeIfPresent([[Lossy<XtreamEpisode>]].self, forKey: .episodes) {
            for list in nested {
                all += list.compactMap(\.value)
            }
        }
        episodes = all.sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
    }
}

public struct XtreamEPGListing: Sendable, Equatable, Hashable {
    public var title: String
    public var details: String?
    public var start: Date
    public var end: Date
    public var channelID: String?

    public init(title: String, details: String? = nil, start: Date, end: Date, channelID: String? = nil) {
        self.title = title
        self.details = details
        self.start = start
        self.end = end
        self.channelID = channelID
    }
}

extension XtreamEPGListing: Decodable {
    private enum CodingKeys: String, CodingKey {
        case title, description, channelID = "channel_id"
        case start = "start_timestamp", end = "stop_timestamp"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let start = container.lenientDate(.start), let end = container.lenientDate(.end) else {
            throw DecodingError.keyNotFound(CodingKeys.start, .init(codingPath: [], debugDescription: "timestamps"))
        }
        self.start = start
        self.end = end
        title = Self.decodeText(container.lenientString(.title)) ?? ""
        details = Self.decodeText(container.lenientString(.description))
        channelID = container.lenientString(.channelID)
    }

    /// Titles and descriptions are base64 on most panels and plain text on a
    /// few. Anything that does not decode to UTF-8 is assumed to be plain.
    private static func decodeText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if let data = Data(base64Encoded: raw), let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return raw
    }
}

/// The result of a successful login.
public struct XtreamAccount: Sendable, Equatable {
    public var username: String
    public var status: String?
    public var expiresAt: Date?
    public var isTrial: Bool
    public var maxConnections: Int?
    public var activeConnections: Int?
    public var allowedFormats: [String]

    public init(
        username: String,
        status: String? = nil,
        expiresAt: Date? = nil,
        isTrial: Bool = false,
        maxConnections: Int? = nil,
        activeConnections: Int? = nil,
        allowedFormats: [String] = []
    ) {
        self.username = username
        self.status = status
        self.expiresAt = expiresAt
        self.isTrial = isTrial
        self.maxConnections = maxConnections
        self.activeConnections = activeConnections
        self.allowedFormats = allowedFormats
    }
}
