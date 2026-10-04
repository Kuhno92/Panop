import PanopCore
import SwiftUI

/// The one title Home puts first: large artwork, its name, one line about it and a way in. The
/// poster is enlarged and softened as the backdrop, since the catalog holds no wide artwork.
struct HeroView: View {
    let row: CatalogRow
    let onPlay: () -> Void
    let onInfo: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        content
            .padding(.horizontal, Self.inset)
            .padding(.top, Self.inset)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background {
                BackdropView(address: row.iconURL, blurred: true)
                    .opacity(0.55)
                    // Fades into the page, so the hero has no hard lower edge.
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea(edges: .top)
            }
    }

    @ViewBuilder
    private var content: some View {
        if sizeClass == .compact {
            VStack(spacing: 14) {
                poster
                text(alignment: .center)
                buttons
            }
        } else {
            HStack(alignment: .bottom, spacing: 28) {
                poster
                VStack(alignment: .leading, spacing: 14) {
                    text(alignment: .leading)
                    buttons
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var poster: some View {
        PosterView(address: row.iconURL, symbol: row.kind == .series ? "rectangle.stack" : "film")
            .frame(width: Self.posterWidth)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    private func text(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(RailHeading.display(row.name))
                .font(Self.titleFont)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
            if let meta {
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Year and the provider's rating, whichever are known.
    private var meta: String? {
        var parts: [String] = []
        if let year = row.year {
            parts.append(String(year))
        }
        if let rating = row.rating, rating > 0 {
            parts.append("★ " + rating.formatted(.number.precision(.fractionLength(1))))
        }
        if let genre = row.genre, !genre.isEmpty {
            parts
                .append(genre.split(separator: ",").first
                    .map { String($0).trimmingCharacters(in: .whitespaces) } ?? genre)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill").frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            Button(action: onInfo) {
                Label("More info", systemImage: "info.circle").frame(minWidth: 90)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(Self.controlSize)
    }

    private static var inset: CGFloat {
        #if os(tvOS)
            60
        #else
            16
        #endif
    }

    private static var posterWidth: CGFloat {
        #if os(tvOS)
            260
        #else
            150
        #endif
    }

    private static var titleFont: Font {
        #if os(tvOS)
            .largeTitle.bold()
        #else
            .title.bold()
        #endif
    }

    private static var controlSize: ControlSize {
        #if os(tvOS)
            .large
        #else
            .regular
        #endif
    }
}
