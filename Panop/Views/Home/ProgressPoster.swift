import SwiftUI

/// A film or an episode left part-way, as a poster with a bar for how far through it is, like
/// Continue Watching on a streaming service. A channel has no poster, so it keeps its logo card.
struct ProgressPoster: View {
    let channel: CatalogEntryRecord
    let isFavorite: Bool
    /// 0 to 1.
    let progress: Double?
    let action: () -> Void

    @Environment(UserStateStore.self) private var userState

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                PosterView(address: channel.iconURL, symbol: channel.kind == .series ? "rectangle.stack" : "film")
                    .frame(width: RailMetrics.posterWidth)
                    .overlay(alignment: .bottom) {
                        if let progress {
                            ProgressBar(fraction: progress)
                                .padding(8)
                                .accessibilityLabel("Watched")
                                .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .shadow(radius: 2)
                                .accessibilityLabel("Favourite")
                        }
                    }
                Text(RailHeading.display(channel.name))
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: RailMetrics.posterWidth, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .hoverZoom(1.08)
        .contextMenu {
            let key = UserStateStore.key(playlist: channel.playlist, entry: channel.id)
            Button {
                userState.toggleFavorite(key)
            } label: {
                Label(
                    isFavorite ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
        }
    }
}

/// A thin bar over artwork: red on a dim track, so it reads on any picture.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(.black.opacity(0.55))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(.red).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
    }
}
