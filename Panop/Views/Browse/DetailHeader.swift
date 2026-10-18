import SwiftUI

/// The top of a film's or a show's page: artwork across the full width, fading into the page, with the
/// poster, the name and a line about it laid over it. The backdrop is the panel's own when it has one,
/// and otherwise the poster enlarged and softened.
struct DetailHeader<Badge: View>: View {
    let backdrop: String?
    let poster: String?
    let title: String
    let meta: String
    var symbol = "film"
    @ViewBuilder var badge: Badge

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            compact
        } else {
            wide
        }
    }

    /// A phone: the picture across the top, as on Home, with the title, the facts and the chips over its lower part.
    private var compact: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(3)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
            if !meta.isEmpty {
                Text(meta).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.78))
            }
            badge
        }
        .padding(.horizontal, Self.inset)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, minHeight: 460, alignment: .bottomLeading)
        .background {
            BackdropView(address: backdrop ?? poster, blurred: false, alignsTop: true)
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5),
                            .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 240)
                }
                // Up under the bar, where the picture begins.
                .ignoresSafeArea(edges: .top)
        }
    }

    private var wide: some View {
        HStack(alignment: .bottom, spacing: Self.gap) {
            PosterView(address: poster, symbol: symbol)
                .frame(width: Self.posterWidth)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Self.titleFont)
                    .lineLimit(3)
                if !meta.isEmpty {
                    Text(meta).font(.subheadline).foregroundStyle(.secondary)
                }
                badge
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, Self.topRoom)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BackdropView(address: backdrop ?? poster, blurred: backdrop == nil)
                .opacity(0.5)
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
        }
    }

    private static var inset: CGFloat {
        #if os(tvOS)
            60
        #else
            16
        #endif
    }

    private static var gap: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }

    /// Room above the poster, so the artwork shows over more than the poster's height.
    private static var topRoom: CGFloat {
        #if os(tvOS)
            80
        #else
            56
        #endif
    }

    private static var posterWidth: CGFloat {
        #if os(tvOS)
            300
        #else
            120
        #endif
    }

    private static var titleFont: Font {
        #if os(tvOS)
            .largeTitle.bold()
        #else
            .title2.bold()
        #endif
    }
}
