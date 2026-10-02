import Foundation

/// What a panel knows about one film, from `get_vod_info`. Fetched when someone opens a film,
/// not for every film in the catalog, so listing stays small.
public struct XtreamMovieInfo: Sendable, Equatable {
    public var plot: String?
    public var cast: String?
    public var director: String?
    public var genre: String?
    public var country: String?
    /// As the panel writes it: a date, or just a year.
    public var releaseDate: String?
    /// Out of ten.
    public var rating: Double?
    public var durationSeconds: Int?
    public var coverURL: String?
    public var backdropURLs: [String]
    /// A YouTube video id or address, when the panel has one.
    public var trailer: String?

    public init(
        plot: String? = nil,
        cast: String? = nil,
        director: String? = nil,
        genre: String? = nil,
        country: String? = nil,
        releaseDate: String? = nil,
        rating: Double? = nil,
        durationSeconds: Int? = nil,
        coverURL: String? = nil,
        backdropURLs: [String] = [],
        trailer: String? = nil
    ) {
        self.plot = plot
        self.cast = cast
        self.director = director
        self.genre = genre
        self.country = country
        self.releaseDate = releaseDate
        self.rating = rating
        self.durationSeconds = durationSeconds
        self.coverURL = coverURL
        self.backdropURLs = backdropURLs
        self.trailer = trailer
    }

    /// The year of release, from whichever form the panel wrote the date in.
    public var year: Int? {
        guard let releaseDate else { return nil }
        let digits = releaseDate.prefix { $0.isNumber }
        if digits.count == 4, let year = Int(digits) {
            return year
        }
        // "05/01/2021" and the like: the four digits wherever they are.
        let parts = releaseDate.split { !$0.isNumber }
        return parts.first { $0.count == 4 }.flatMap { Int($0) }
    }
}

extension XtreamMovieInfo: Decodable {
    private enum CodingKeys: String, CodingKey { case info }

    private enum InfoKeys: String, CodingKey {
        case plot, description, cast, actors, director, genre, country
        case releaseDate = "releasedate", releaseDateAlt = "release_date", year
        case rating, rating5 = "rating_5based"
        case durationSeconds = "duration_secs", duration
        case cover = "movie_image", coverAlt = "cover_big"
        case backdrop = "backdrop_path", trailer = "youtube_trailer"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown film comes back as `"info": []`, which is not an object.
        guard let info = try? container.nestedContainer(keyedBy: InfoKeys.self, forKey: .info) else {
            self.init()
            return
        }
        self.init(
            plot: info.lenientString(.plot) ?? info.lenientString(.description),
            cast: info.lenientString(.cast) ?? info.lenientString(.actors),
            director: info.lenientString(.director),
            genre: info.lenientString(.genre),
            country: info.lenientString(.country),
            releaseDate: info.lenientString(.releaseDate) ?? info.lenientString(.releaseDateAlt)
                ?? info.lenientString(.year),
            rating: info.lenientDouble(.rating).flatMap { $0 > 0 ? $0 : nil }
                ?? info.lenientDouble(.rating5).flatMap { $0 > 0 ? $0 * 2 : nil },
            durationSeconds: info.lenientInt(.durationSeconds).flatMap { $0 > 0 ? $0 : nil }
                ?? Self.seconds(fromClock: info.lenientString(.duration)),
            coverURL: info.lenientString(.cover) ?? info.lenientString(.coverAlt),
            backdropURLs: info.lenientStrings(.backdrop),
            trailer: info.lenientString(.trailer)
        )
    }

    /// `01:32:10` or `92:10`, which some panels send instead of a number of seconds.
    static func seconds(fromClock text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2, parts.count <= 3, !parts.contains(where: { $0 == nil }) else { return nil }
        let seconds = parts.compactMap(\.self).reduce(0) { $0 * 60 + $1 }
        return seconds > 0 ? seconds : nil
    }
}
