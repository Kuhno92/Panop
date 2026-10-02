import PanopCore
import PanopDiscover
import PanopSimkl
import SwiftUI

/// The heading of a rail, in words.
nonisolated enum RailHeading {
    static func title(for rail: Rail) -> String {
        switch rail.kind {
        case .nextUp:
            "Next up on Simkl"
        case .onYourList:
            "On your Simkl list"
        case let .trending(kind):
            kind == .series ? "Trending series on Simkl" : "Trending movies on Simkl"
        case .becauseYouWatched:
            "Because you watched \(display(rail.subject))"
        case let .newReleases(kind):
            kind == .series ? "New series" : "New movies"
        case .mostWatched:
            "Watch again"
        case let .topRated(kind):
            kind == .series ? "Top rated series" : "Top rated movies"
        case let .genre(kind, _):
            "\(rail.subject?.capitalized ?? "More") \(kind == .series ? "series" : "movies")"
        case .franchise:
            "More from \(rail.subject?.capitalized ?? "this series")"
        case .classics:
            "Classics"
        case let .decade(_, decade):
            "Movies of the \(decade)s"
        case let .pickOfTheDay(kind):
            kind == .series ? "Series pick of the day" : "Movie pick of the day"
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
        guard case .trending = rail.kind, let id = row.tmdbID else { return nil }
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
        case let .trending(kind), let .newReleases(kind), let .topRated(kind), let .genre(kind, _),
             let .classics(kind), let .decade(kind, _), let .pickOfTheDay(kind):
            kind
        case .franchise:
            .movie
        case .becauseYouWatched, .mostWatched, .onYourList, .nextUp:
            nil
        }
    }
}
