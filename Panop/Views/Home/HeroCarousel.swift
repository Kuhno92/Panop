import SwiftUI

/// The hero as a carousel: several titles that slide by themselves, a swipe (or the dots) to move by hand, and a
/// pause while someone is on a button or has just moved it. With Reduce Motion on it does not slide at all.
struct HeroCarousel: View {
    let rows: [CatalogRow]
    let backdrop: (CatalogRow) -> String?
    /// Nil where playing straight away is not on offer (the Movies and Series screens).
    var onPlay: ((CatalogRow) -> Void)?
    let onInfo: (CatalogRow) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var index = 0
    /// A button in the hero has focus, or a finger has just moved it: not the moment to slide away.
    @State private var engaged = false

    private static let interval = Duration.seconds(7)

    private var current: Int {
        rows.isEmpty ? 0 : min(index, rows.count - 1)
    }

    private struct Timer: Equatable {
        var count: Int
        var index: Int
        var engaged: Bool
    }

    var body: some View {
        if !rows.isEmpty {
            let row = rows[current]
            ZStack(alignment: .bottom) {
                HeroView(
                    row: row,
                    backdrop: backdrop(row),
                    onPlay: onPlay.map { play in { play(row) } },
                    onInfo: { onInfo(row) },
                    engaged: $engaged,
                    showsBackdrop: false,
                    onStep: { move(by: $0) }
                )
                .id(row.id)
                .transition(.opacity)
                if rows.count > 1 {
                    dots
                }
                #if !os(tvOS)
                    if rows.count > 1, sizeClass != .compact {
                        arrows
                    }
                #endif
            }
            // The artwork is its own layer behind the slides, crossfading while they stay put. As a background it
            // reaches up under the bar without moving the slides, and it is not clipped, so it fades into the rows.
            // Anchored at the bottom, so what it gains by reaching under the bars goes upward, to the top of the
            // screen as on a film's page, and never down over the rows (where it would block them).
            .background(alignment: .bottom) {
                HeroArtwork(address: backdrop(row) ?? row.iconURL, blurred: backdrop(row) == nil)
                    .id("art-" + row.id)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            // One height for every slide, so the page below does not move as titles change.
            .frame(height: Self.height(compact: sizeClass == .compact))
            // Above the rows that follow it, so the dots are never behind them.
            .zIndex(1)
            #if !os(tvOS)
                .simultaneousGesture(swipe)
            #endif
                .task(id: Timer(count: rows.count, index: current, engaged: engaged)) { await slide() }
                .accessibilityElement(children: .contain)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: move(by: 1)
                    case .decrement: move(by: -1)
                    @unknown default: break
                    }
                }
        }
    }

    /// Where on the carousel it stands, and a way to go to one: each dot is a button where there is a pointer or a
    /// finger. Apple TV moves by the remote, and its dots only show.
    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { position in
                #if os(tvOS)
                    dot(position)
                #else
                    Button { go(to: position) } label: {
                        dot(position)
                            // A larger target than the dot itself.
                            .padding(.vertical, 12)
                            .padding(.horizontal, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Featured title \(position + 1) of \(rows.count)")
                #endif
            }
        }
        .padding(.bottom, 8)
    }

    private func dot(_ position: Int) -> some View {
        Capsule()
            .fill(position == current ? Color.primary : Color.primary.opacity(0.3))
            .frame(width: position == current ? 18 : 6, height: 6)
    }

    #if !os(tvOS)
        /// Previous and next, at the sides, where there is room for them: a pointer has no swipe.
        private var arrows: some View {
            HStack {
                arrow("chevron.left", step: -1, label: "Previous title")
                Spacer()
                arrow("chevron.right", step: 1, label: "Next title")
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
        }

        private func arrow(_ symbol: String, step: Int, label: LocalizedStringKey) -> some View {
            Button { move(by: step) } label: {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    #endif

    private func go(to position: Int) {
        engaged = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { index = position }
    }

    #if !os(tvOS)
        private var swipe: some Gesture {
            DragGesture(minimumDistance: 24).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                move(by: drag.translation.width < 0 ? 1 : -1)
            }
        }
    #endif

    private func move(by step: Int) {
        guard rows.count > 1 else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            index = (current + step + rows.count) % rows.count
        }
    }

    /// Waits, then moves on. Keyed on the position and on `engaged`, so a move by hand or a button taking focus
    /// starts the wait again.
    private func slide() async {
        guard rows.count > 1, !engaged, !reduceMotion else { return }
        try? await Task.sleep(for: Self.interval)
        guard !Task.isCancelled else { return }
        move(by: 1)
    }

    private static func height(compact: Bool) -> CGFloat {
        #if os(tvOS)
            540
        #else
            compact ? 480 : 320
        #endif
    }
}
