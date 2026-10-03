import PanopCore
import PanopDiscover
import PanopSimkl
import SwiftUI

/// The heading of a rail, in words.
nonisolated enum RailHeading {
    /// A list made from Simkl's. Each names Simkl, as its terms ask of anything shown from its data.
    private static func curatedTitle(_ kind: MediaKind, _ id: String) -> String {
        switch id {
        case "boxOffice":
            return String(localized: "Top Box Office Movies on Simkl")
        case "inTheatres":
            return String(localized: "In Theatres Now on Simkl")
        case "justOnDVD":
            return String(localized: "Latest DVD Releases on Simkl")
        case "quickWatches":
            return String(localized: "Quick Watches on Simkl (90 min or less)")
        case "airing":
            return String(localized: "Currently Airing Series on Simkl")
        case "premieres":
            return forKind(
                kind,
                series: String(localized: "Trending Series Premieres on Simkl"),
                movies: String(localized: "Trending Movie Premieres on Simkl")
            )
        case "hiddenGems":
            return forKind(
                kind,
                series: String(localized: "Hidden Gem Series on Simkl"),
                movies: String(localized: "Hidden Gem Movies on Simkl")
            )
        case "topRated":
            return forKind(
                kind,
                series: String(localized: "Top Rated Series on Simkl"),
                movies: String(localized: "Top Rated Movies on Simkl")
            )
        case "mostWatchlisted":
            return forKind(
                kind,
                series: String(localized: "Most Watchlisted Series on Simkl"),
                movies: String(localized: "Most Watchlisted Movies on Simkl")
            )
        default:
            if id.hasPrefix("genre.") {
                let genre = genreName(String(id.dropFirst("genre.".count)))
                return forKind(
                    kind,
                    series: String(localized: "Best \(genre) Series on Simkl"),
                    movies: String(localized: "Best \(genre) Movies on Simkl")
                )
            }
            if id.hasPrefix("decade.") {
                let decade = String(id.dropFirst("decade.".count))
                return String(localized: "Best Movies of the \(decade)s on Simkl")
            }
            if id.hasPrefix("network.") {
                let network = String(id.dropFirst("network.".count))
                return String(localized: "Best of \(network) on Simkl")
            }
            return id
        }
    }

    private static func genreName(_ genre: String) -> String {
        switch genre {
        case "Action": String(localized: "Action")
        case "Drama": String(localized: "Drama")
        case "Comedy": String(localized: "Comedy")
        case "Science Fiction": String(localized: "Sci-Fi")
        case "Thriller": String(localized: "Thriller")
        case "Horror": String(localized: "Horror")
        case "Crime": String(localized: "Crime")
        default: genre
        }
    }

    /// The wording for a series or for a film.
    private static func forKind(_ kind: MediaKind, series: String, movies: String) -> String {
        kind == .series ? series : movies
    }

    static func title(for rail: Rail) -> String {
        switch rail.kind {
        case .nextUp:
            String(localized: "Next up on Simkl")
        case .onYourList:
            String(localized: "On your Simkl list")
        case let .curated(kind, id):
            curatedTitle(kind, id)
        case let .trending(kind):
            forKind(
                kind,
                series: String(localized: "Trending series on Simkl"),
                movies: String(localized: "Trending movies on Simkl")
            )
        case .becauseYouWatched:
            String(localized: "Because you watched \(display(rail.subject))")
        case let .newReleases(kind):
            forKind(kind, series: String(localized: "New series"), movies: String(localized: "New movies"))
        case .mostWatched:
            String(localized: "Watch again")
        case let .topRated(kind):
            forKind(kind, series: String(localized: "Top rated series"), movies: String(localized: "Top rated movies"))
        case let .genre(kind, _):
            forKind(
                kind,
                series: String(localized: "\(rail.subject?.capitalized ?? "More") series"),
                movies: String(localized: "\(rail.subject?.capitalized ?? "More") movies")
            )
        case .franchise:
            String(localized: "More from \(rail.subject?.capitalized ?? "this series")")
        case .classics:
            String(localized: "Classics")
        case let .decade(_, decade):
            String(localized: "Movies of the \(String(decade))s")
        case let .pickOfTheDay(kind):
            forKind(
                kind,
                series: String(localized: "Series pick of the day"),
                movies: String(localized: "Movie pick of the day")
            )
        }
    }

    /// A title as a person would write it: without the provider's language tag, year and brackets.
    static func display(_ name: String?) -> String {
        guard let name else { return "" }
        let cleaned = TitleText.clean(name)
        return cleaned.isEmpty ? name : cleaned
    }
}

/// A row of posters under a heading. Draws what it is given; the titles were chosen off the main thread.
struct PosterRail: View {
    let rail: Rail
    let rows: [String: CatalogRow]
    /// Simkl's page for a title, for the trending rails.
    var links: [String: URL] = [:]
    /// The episode to watch next, by the same key, for the rail of followed shows.
    var nextEpisodes: [String: SimklNextEpisode] = [:]
    let onSelect: (CatalogRow) -> Void

    var body: some View {
        let items = rail.keys.compactMap { rows[$0] }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(RailHeading.title(for: rail))
                    .font(.title2.bold())
                    .padding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(items) { row in
                            RailPoster(row: row, link: link(for: row), caption: caption(for: row)) { onSelect(row) }
                        }
                    }
                    .padding(.horizontal)
                    // A focused poster on Apple TV grows, and the row would clip it.
                    .padding(.vertical, Self.verticalRoom)
                }
            }
        }
    }

    /// Only a trending rail carries Simkl's data, so only there is there a page to link to.
    private func link(for row: CatalogRow) -> URL? {
        switch rail.kind {
        case .trending, .curated: break
        default: return nil
        }
        guard let id = row.tmdbID else { return nil }
        return links[DiscoveryModel.linkKey(kind: row.kind, tmdbID: id)]
    }

    private func caption(for row: CatalogRow) -> String? {
        guard case .nextUp = rail.kind, let id = row.tmdbID else { return nil }
        return nextEpisodes[DiscoveryModel.linkKey(kind: row.kind, tmdbID: id)]?.label
    }

    private static var spacing: CGFloat {
        #if os(tvOS)
            40
        #else
            14
        #endif
    }

    private static var verticalRoom: CGFloat {
        #if os(tvOS)
            24
        #else
            0
        #endif
    }
}

private struct RailPoster: View {
    let row: CatalogRow
    let link: URL?
    let caption: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                PosterView(address: row.iconURL, symbol: row.kind == .series ? "rectangle.stack" : "film")
                    .frame(width: Self.width)
                Text(RailHeading.display(row.name))
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: Self.width, alignment: .leading)
                if let caption {
                    Text(caption)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(RailHeading.display(row.name))
        .contextMenu {
            if let link {
                Link("View on Simkl", destination: link)
            }
        }
    }

    private static var width: CGFloat {
        #if os(tvOS)
            200
        #else
            110
        #endif
    }
}

extension Rail {
    /// Whether the rail holds films or series, for a screen that shows only its own. Nil for the rails
    /// that mix both.
    nonisolated var mediaKind: MediaKind? {
        switch kind {
        case let .trending(kind), let .newReleases(kind), let .topRated(kind), let .genre(kind, _), let .curated(
            kind,
            _
        ),
        let .classics(kind), let .decade(kind, _), let .pickOfTheDay(kind):
            kind
        case .franchise:
            .movie
        case .becauseYouWatched, .mostWatched, .onYourList, .nextUp:
            nil
        }
    }
}
