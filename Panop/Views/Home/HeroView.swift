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
            .padding(.bottom, 20)
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
            if let onPlay {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill").frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .focused($focus, equals: .play)
                Button(action: onInfo) {
                    Label("More info", systemImage: "info.circle").frame(minWidth: 90)
                }
                .buttonStyle(.bordered)
                .focused($focus, equals: .info)
            } else {
                Button(action: onInfo) {
                    Label("More info", systemImage: "info.circle").frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
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

/// The artwork behind a hero: wide where there is some, otherwise the poster enlarged and softened, faded away at
/// the bottom so it runs into the rows below instead of ending in an edge, and reaching up under the bar.
struct HeroArtwork: View {
    let address: String?
    let blurred: Bool

    var body: some View {
        BackdropView(address: address, blurred: blurred)
            .opacity(0.55)
            .mask(LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.45),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
            .ignoresSafeArea(edges: .top)
    }
}
