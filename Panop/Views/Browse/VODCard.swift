import PanopCore
import SwiftUI

/// One poster, its title, and how far through it someone got.
struct VODCard: View {
    let item: CatalogRow
    let kind: MediaKind
    let action: () -> Void

    @Environment(UserStateStore.self) private var userState

    private var key: String {
        item.id
    }

    private static var namePadding: CGFloat {
        #if os(tvOS)
            14
        #else
            0
        #endif
    }

    var body: some View {
        let isFavorite = userState.isFavorite(key)
        let fraction = userState.progress[key]?.fraction
        let isWatched = userState.isWatched(key)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                PosterView(address: item.iconURL, symbol: kind == .movie ? "film" : "rectangle.stack")
                    .overlay(alignment: .bottom) {
                        if let fraction {
                            ProgressView(value: fraction)
                                .tint(.white)
                                .padding(8)
                                .accessibilityLabel("Watched \(Int(fraction * 100)) percent")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .accessibilityLabel("Favourite")
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let rating = item.rating, rating > 0 {
                            Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.65), in: Capsule())
                                // Above the progress bar when there is one.
                                .padding(.leading, 6)
                                .padding(.bottom, fraction == nil ? 6 : 22)
                                .accessibilityLabel("Rated \(rating.formatted(.number.precision(.fractionLength(1))))")
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isWatched {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, .green)
                                .padding(6)
                                .accessibilityLabel("Watched")
                        }
                    }
                Text(item.name)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // Room round the name, so it does not sit on the card's edge (the card style on Apple TV
                    // draws one round the poster and the name).
                    .padding(.horizontal, Self.namePadding)
                    .padding(.bottom, Self.namePadding)
            }
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(item.name)
        .hoverZoom(1.07)
        .contextMenu {
            Button {
                userState.toggleFavorite(key)
            } label: {
                Label(
                    isFavorite ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
            // A series entry is a show, which is watched through its episodes.
            Button {
                userState.setHidden(true, for: key)
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            if kind == .movie {
                Button {
                    userState.setWatched(!isWatched, for: key)
                } label: {
                    Label(
                        isWatched ? "Mark as Not Watched" : "Mark as Watched",
                        systemImage: isWatched ? "eye.slash" : "eye"
                    )
                }
            }
        }
    }
}
