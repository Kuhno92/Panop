import PanopCore
import SwiftUI

/// The one title Home puts first: large artwork, its name, one line about it and a way in. The
/// poster is enlarged and softened as the backdrop, since the catalog holds no wide artwork.
struct HeroView: View {
    let row: CatalogRow
    /// Wide artwork for it, when there is some; otherwise the poster, enlarged and softened.
    var backdrop: String?
    /// Nil where playing straight away is not on offer, and the one button is for the title's page.
    var onPlay: (() -> Void)?
    let onInfo: () -> Void

    /// Set while a button in the hero has focus, so a carousel around it does not slide away from under the person.
    var engaged: Binding<Bool> = .constant(false)
    /// False where the carousel around it draws the artwork once, behind every slide, so it can fade as one.
    var showsBackdrop = true
    /// Asks a carousel around it for the next or the previous title: on Apple TV, a press past the last button.
    var onStep: ((Int) -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var focus: Control?

    private enum Control { case play, info }

    var body: some View {
        content
            .padding(.horizontal, Self.inset)
            .padding(.top, Self.inset)
            .padding(.bottom, sizeClass == .compact ? 36 : 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                if showsBackdrop {
                    HeroArtwork(address: backdrop ?? row.iconURL, blurred: backdrop == nil)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if sizeClass == .compact {
            // The poster is the page's artwork (`HeroArtwork`, full width), so what is left is the title and the way
            // in,
            // at the bottom, over it.
            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 0)
                text(alignment: .leading)
                buttons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // The words on the left and the poster on the right, large, with a glow of the accent behind it: what a
            // screen across the room reads first.
            HStack(alignment: .bottom, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    text(alignment: .leading)
                    buttons
                }
                Spacer(minLength: 0)
                poster
                    .background {
                        Circle()
                            .fill(RadialGradient(
                                colors: [Theme.violet.opacity(0.7), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: Self.posterWidth * 1.1
                            ))
                            .frame(width: Self.posterWidth * 2.4, height: Self.posterWidth * 2.4)
                    }
            }
        }
    }

    private var poster: some View {
        PosterView(address: row.iconURL, symbol: row.kind == .series ? "rectangle.stack" : "film")
            .frame(width: Self.posterWidth)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    private func text(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(RailHeading.display(row.name))
                .font(Self.titleFont)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
            if let meta {
                Text(meta)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
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
            if let onPlay {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill").frame(minWidth: 90)
                }
                .heroButton(prominent: true)
                .focused($focus, equals: .play)
                Button(action: onInfo) {
                    Label("More info", systemImage: "info.circle").frame(minWidth: 90)
                }
                .heroButton(prominent: false)
                .focused($focus, equals: .info)
            } else {
                Button(action: onInfo) {
                    Label("More info", systemImage: "info.circle").frame(minWidth: 90)
                }
                .heroButton(prominent: true)
                .focused($focus, equals: .info)
            }
        }
        .controlSize(Self.controlSize)
        #if os(tvOS)
            // Past the last button on either side is the way to the next title; between them it is just focus.
            .onMoveCommand { direction in
                switch (direction, focus) {
                case (.left, .play), (.left, .info) where onPlay == nil:
                    onStep?(-1)
                case (.right, .info):
                    onStep?(1)
                default:
                    break
                }
            }
        #endif
            .onChange(of: focus) { _, now in engaged.wrappedValue = now != nil }
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
            300
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

extension EnvironmentValues {
    /// How far a hero's artwork reaches up past its content, to the top of the screen (see `HeroArtwork.reach`).
    @Entry var heroReach: CGFloat = 0
}

/// The artwork behind a hero: wide where there is some, otherwise the poster enlarged and softened, faded away at
/// the bottom so it runs into the rows below instead of ending in an edge, and reaching up under the bar.
struct HeroArtwork: View {
    let address: String?
    let blurred: Bool
    /// How far to reach up past the top of the content, to the top of the screen. Inside a scroll view
    /// `ignoresSafeArea`
    /// does not do it on iPhone and iPad: the content starts below the navigation bar, and so did the artwork.
    var reach: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tint = Theme.violet

    /// A phone's hero is the poster itself, full width and sharp, since it is the picture there is; elsewhere the
    /// artwork is a soft wash behind the poster.
    private var fullBleed: Bool {
        sizeClass == .compact && blurred
    }

    var body: some View {
        BackdropView(address: address, blurred: blurred && !fullBleed, alignsTop: fullBleed) { tint = $0 }
            .opacity(fullBleed ? 0.95 : 0.8)
            .saturation(fullBleed ? 1 : 1.35)
            .mask(LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: fullBleed ? 0.42 : 0.45),
                    .init(color: .clear, location: fullBleed ? 0.98 : 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
            // The title's own colour, glowing from the top corner: the page takes on the look of what is shown.
            .background(alignment: .topTrailing) {
                RadialGradient(
                    colors: [tint.opacity(fullBleed ? 0.25 : 0.45), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 520
                )
                .animation(.easeInOut(duration: 0.6), value: tint)
                .allowsHitTesting(false)
            }
            // Dark behind the clock and the title above the picture, and under the title and buttons below it, where
            // a poster's own small print would otherwise run through them.
            .overlay {
                if fullBleed {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 140)
                        Spacer(minLength: 0)
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 260)
                    }
                    .allowsHitTesting(false)
                }
            }
        // Edge to edge: on Apple TV the safe area is a margin of the screen's own, and the artwork stopped short of
        // it.
        #if os(iOS)
            // `reach` does the top on iPhone and iPad; ignoring the top safe area as well drew the artwork above its
            // neighbours, over the buttons that sit above the hero.
            .ignoresSafeArea(edges: .horizontal)
        #else
            .ignoresSafeArea(edges: [.top, .horizontal])
        #endif
            .padding(.top, -reach)
    }
}

private extension View {
    /// The hero's two buttons: Panop's pills, and on Apple TV the system's, which carry the focus effect.
    @ViewBuilder
    func heroButton(prominent: Bool) -> some View {
        #if os(tvOS)
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        #else
            buttonStyle(PillButtonStyle(prominent: prominent))
        #endif
    }
}
