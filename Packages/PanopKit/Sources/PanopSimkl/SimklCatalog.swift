import Foundation
import PanopCore
import PanopDiscover

/// One title from one of Simkl's public lists, with what the lists say about it: enough to build "Top Box
/// Office" or "Best of Netflix" without asking anything more.
public struct SimklTitle: Sendable, Equatable {
    public var kind: MediaKind
    public var tmdbID: Int
    /// Simkl's own page for it, which anything shown from Simkl's data links back to.
    public var link: String?
    /// Where it comes in the list it was read from, 0 being first.
    public var position: Int
    public var genres: [String]
    /// The channel or service, for series.
    public var network: String?
    public var simklRating: Double?
    public var simklVotes: Int
    public var imdbRating: Double?
    public var imdbVotes: Int
    public var releaseDate: Date?
    public var theatricalDate: Date?
    public var dvdDate: Date?
    public var runtimeMinutes: Int?
    /// In US dollars.
    public var boxOffice: Double?
    public var status: String?
    /// How many have it on a plan-to-watch list, and how many have watched it.
    public var watchlisted: Int
    public var watched: Int

    public init(
        kind: MediaKind, tmdbID: Int, link: String? = nil, position: Int = 0, genres: [String] = [],
        network: String? = nil, simklRating: Double? = nil, simklVotes: Int = 0, imdbRating: Double? = nil,
        imdbVotes: Int = 0, releaseDate: Date? = nil, theatricalDate: Date? = nil, dvdDate: Date? = nil,
        runtimeMinutes: Int? = nil, boxOffice: Double? = nil, status: String? = nil, watchlisted: Int = 0,
        watched: Int = 0
    ) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.link = link
        self.position = position
        self.genres = genres
        self.network = network
        self.simklRating = simklRating
        self.simklVotes = simklVotes
        self.imdbRating = imdbRating
        self.imdbVotes = imdbVotes
        self.releaseDate = releaseDate
        self.theatricalDate = theatricalDate
        self.dvdDate = dvdDate
        self.runtimeMinutes = runtimeMinutes
        self.boxOffice = boxOffice
        self.status = status
        self.watchlisted = watchlisted
        self.watched = watched
    }

    /// How well it is rated, out of ten: IMDb's and Simkl's averaged, each counted only when enough people
    /// voted for it to mean something. Nil when neither is.
    public var score: Double? {
        var parts: [Double] = []
        if imdbVotes >= 2000, let imdbRating {
            parts.append(imdbRating)
        }
        if simklVotes >= 50, let simklRating {
            parts.append(simklRating)
        }
        return parts.isEmpty ? nil : parts.reduce(0, +) / Double(parts.count)
    }

    public var year: Int? {
        releaseDate.map { Calendar.simkl.component(.year, from: $0) }
    }

    func hasGenre(_ name: String) -> Bool {
        let wanted = Self.normalised(name)
        return genres.contains { Self.normalised($0) == wanted }
    }

    /// `Science Fiction` and `Science-Fiction` are one genre.
    static func normalised(_ genre: String) -> String {
        genre.lowercased().replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

extension Calendar {
    /// Simkl's dates are calendar dates, read the same everywhere.
    static let simkl: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

/// Reads one of Simkl's list files, leniently: a title that is odd costs that title, and a field that is
/// missing costs that field.
public enum SimklFile {
    public static func titles(from data: Data, kind: MediaKind) -> [SimklTitle]? {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return items.enumerated().compactMap { index, item in title(from: item, kind: kind, position: index) }
    }

    static func title(from item: [String: Any], kind: MediaKind, position: Int) -> SimklTitle? {
        let ids = item["ids"] as? [String: Any]
        guard let tmdb = integer(ids?["tmdb"]), tmdb > 0 else { return nil }
        let ratings = item["ratings"] as? [String: Any]
        let simkl = ratings?["simkl"] as? [String: Any]
        let imdb = ratings?["imdb"] as? [String: Any]
        let metadata = item["metadata"] as? String
        return SimklTitle(
            kind: kind,
            tmdbID: tmdb,
            link: (item["url"] as? String).map { "https://simkl.com" + $0 },
            position: position,
            genres: unique((item["genres"] as? [String]) ?? []),
            network: item["network"] as? String,
            simklRating: double(simkl?["rating"]),
            simklVotes: integer(simkl?["votes"]) ?? 0,
            imdbRating: double(imdb?["rating"]),
            imdbVotes: integer(imdb?["votes"]) ?? 0,
            releaseDate: date(item["release_date"]),
            theatricalDate: date(item["theater"]),
            dvdDate: date(item["dvd_date"]),
            runtimeMinutes: (item["runtime"] as? String).flatMap(minutes),
            boxOffice: metadata.flatMap(boxOffice),
            status: item["status"] as? String,
            watchlisted: integer(item["plan_to_watch"]) ?? 0,
            watched: integer(item["watched"]) ?? 0
        )
    }

    // MARK: - Fields

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int {
            return number
        }
        if let text = value as? String {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        return (value as? Double).flatMap { $0.isFinite ? Int($0) : nil }
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? Double {
            return number
        }
        return (value as? String).flatMap { Double($0) }
    }

    private static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    /// `08/12/2026`, month first.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let parts = text.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let wanted = DateComponents(year: parts[2], month: parts[0], day: parts[1])
        // A calendar rolls an impossible date (month 13, day 45) forward instead of refusing it, so the
        // date has to read back as what was written.
        guard let made = Calendar.simkl.date(from: wanted),
              Calendar.simkl.dateComponents([.year, .month, .day], from: made) == wanted else { return nil }
        return made
    }

    /// `1h 40m`, `2h`, `45m`.
    static func minutes(_ text: String) -> Int? {
        var total = 0
        var number = ""
        var found = false
        for character in text {
            if character.isNumber {
                number.append(character)
            } else if character == "h" || character == "m", let value = Int(number) {
                total += character == "h" ? value * 60 : value
                number = ""
                found = true
            } else {
                number = ""
            }
        }
        return found ? total : nil
    }

    /// `… • Budget $85M • Box office $2,496M` as dollars. Thousands, millions and billions.
    static func boxOffice(_ metadata: String) -> Double? {
        guard let range = metadata.range(of: "Box office $") else { return nil }
        var digits = ""
        var suffix: Character?
        for character in metadata[range.upperBound...] {
            if character.isNumber || character == "." {
                digits.append(character)
            } else if character == "," {
                continue
            } else {
                suffix = character
                break
            }
        }
        guard let value = Double(digits) else { return nil }
        switch suffix {
        case "B": return value * 1_000_000_000
        case "M": return value * 1_000_000
        case "K": return value * 1000
        default: return value
        }
    }
}
