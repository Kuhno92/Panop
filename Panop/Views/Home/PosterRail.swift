import PanopDiscover
import SwiftUI

/// The heading of a rail, in words.
nonisolated enum RailHeading {
    static func title(for rail: Rail) -> String {
        switch rail.kind {
        case let .trending(kind):
            kind == .series ? "Trending series" : "Trending movies"
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
                            RailPoster(row: row) { onSelect(row) }
                        }
                    }
                    .padding(.horizontal)
                    // A focused poster on Apple TV grows, and the row would clip it.
                    .padding(.vertical, Self.verticalRoom)
                }
            }
        }
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
            }
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(RailHeading.display(row.name))
    }

    private static var width: CGFloat {
        #if os(tvOS)
            200
        #else
            110
        #endif
    }
}
