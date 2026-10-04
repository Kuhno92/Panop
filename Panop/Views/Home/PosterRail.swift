import PanopCore
import PanopDiscover
import PanopSimkl
import SwiftUI

/// The heading of a rail, in words.
nonisolated enum RailHeading {
    /// The name of one of the person's own lists, or nil for a list that is not one.
    private static func customTitle(_ rail: Rail, _ id: String) -> String? {
        guard id.hasPrefix("custom.") else { return nil }
        return String(localized: "Your list: \(rail.subject ?? "")")
    }

    /// A list made from Simkl's. Each names Simkl, as its terms ask of anything shown from its data.
    private static func curatedTitle(_ kind: MediaKind, _ id: String) -> String {
        switch id {
        case "boxOffice":
            return String(localized: "Top Box Office Movies")
        case "inTheatres":
            return String(localized: "In Theatres Now")
        case "justOnDVD":
            return String(localized: "Latest DVD Releases")
        case "quickWatches":
            return String(localized: "Quick Watches (90 min or less)")
        case "airing":
            return String(localized: "Currently Airing Series")
        case "premieres":
            return forKind(
                kind,
                series: String(localized: "Trending Series Premieres"),
                movies: String(localized: "Trending Movie Premieres")
            )
        case "hiddenGems":
            return forKind(
                kind,
                series: String(localized: "Hidden Gem Series"),
                movies: String(localized: "Hidden Gem Movies")
            )
        case "topRated":
            return forKind(
                kind,
                series: String(localized: "Top Rated Series"),
                movies: String(localized: "Top Rated Movies")
            )
        case "mostWatchlisted":
            return forKind(
                kind,
                series: String(localized: "Most Watchlisted Series"),
                movies: String(localized: "Most Watchlisted Movies")
            )
        default:
            if id.hasPrefix("genre.") {
                let genre = genreName(String(id.dropFirst("genre.".count)))
                return forKind(
                    kind,
                    series: String(localized: "Best \(genre) Series"),
                    movies: String(localized: "Best \(genre) Movies")
                )
            }
            if id.hasPrefix("decade.") {
                let decade = String(id.dropFirst("decade.".count))
                return String(localized: "Best Movies of the \(decade)s")
            }
            if id.hasPrefix("network.") {
                let network = String(id.dropFirst("network.".count))
                return String(localized: "Best of \(network)")
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

    /// Whether the rail is made from Simkl's data, and so carries its mark.
    static func isFromSimkl(_ rail: Rail) -> Bool {
        switch rail.kind {
        case .nextUp, .onYourList, .curated, .trending: true
        default: false
        }
    }

    static func title(for rail: Rail) -> String {
        switch rail.kind {
        case .nextUp:
            String(localized: "Next up")
        case .onYourList:
            String(localized: "On your list")
        case let .curated(kind, id):
            // A list the person named themselves is called what they called it.
            customTitle(rail, id) ?? curatedTitle(kind, id)
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
        }
    }

    /// A title as a person would write it: without the provider's language tag, year and brackets.
    static func display(_ name: String?) -> String {
        guard let name else { return "" }
        let cleaned = TitleText.clean(name)
        return cleaned.isEmpty ? name : cleaned
    }
}

/// Simkl's own mark, the colored icon it provides for apps that show its data, at the start of a heading.
struct SimklMark: View {
    var body: some View {
        Image("SimklLogo")
            .resizable()
            .scaledToFit()
            .frame(width: Self.size, height: Self.size)
            .clipShape(RoundedRectangle(cornerRadius: Self.size * 0.22))
            .accessibilityLabel("Simkl")
    }

    private static var size: CGFloat {
        #if os(tvOS)
            40
        #else
            24
        #endif
    }
}

/// The one line of credit for Simkl's data that Simkl's rules ask for where it is shown.
struct SimklCredit: View {
    var body: some View {
        Text("Movie, TV and anime data from Simkl")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
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
                HStack(spacing: 10) {
                    if RailHeading.isFromSimkl(rail) {
                        SimklMark()
                    }
                    Text(RailHeading.title(for: rail))
                        .font(.title2.bold())
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: RailMetrics.spacing) {
                        ForEach(items) { row in
                            RailPoster(row: row, link: link(for: row), caption: caption(for: row)) { onSelect(row) }
                        }
                    }
                    .padding(.horizontal)
                    // A focused poster on Apple TV grows, and the row would clip it.
                    .padding(.vertical, RailMetrics.verticalRoom)
                }
                .scrollClipDisabled()
            }
            .hoverZoom(1.03, anchor: .leading, lifts: false)
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
        .hoverZoom(1.08)
        .contextMenu {
            if let link {
                Link("View on Simkl", destination: link)
            }
        }
    }

    private static var width: CGFloat {
        RailMetrics.posterWidth
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
        let .classics(kind), let .decade(kind, _):
            kind
        case .franchise:
            .movie
        case .becauseYouWatched, .mostWatched, .onYourList, .nextUp:
            nil
        }
    }
}
