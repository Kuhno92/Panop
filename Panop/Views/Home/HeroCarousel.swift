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
                    engaged: $engaged
                )
                .id(row.id)
                .transition(.opacity)
                if rows.count > 1 {
                    dots
                }
            }
            // One height for every slide, so the page below does not move as titles change.
            .frame(height: Self.height(compact: sizeClass == .compact))
            .clipped()
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

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { position in
                Capsule()
                    .fill(position == current ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: position == current ? 18 : 6, height: 6)
            }
        }
        .padding(.bottom, 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            500
        #else
            compact ? 480 : 300
        #endif
    }
}
