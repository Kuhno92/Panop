import SwiftUI

/// Grows a view a little while a pointer is over it, so what would be chosen stands out. A rail grows slightly and
/// the poster under the pointer more, which together read as lifting one title out of a row. Apple TV has its own
/// focus effect, and a touch screen has no hover, so there it does nothing.
struct HoverZoom: ViewModifier {
    let scale: CGFloat
    var anchor: UnitPoint = .center
    var lifts = true

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(tvOS)
            content
        #else
            content
                .scaleEffect(hovering ? scale : 1, anchor: anchor)
                .shadow(color: .black.opacity(hovering && lifts ? 0.35 : 0), radius: 14, y: 6)
                // Above its neighbours while it overlaps them.
                .zIndex(hovering ? 1 : 0)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: hovering)
        #endif
    }
}

extension View {
    func hoverZoom(_ scale: CGFloat, anchor: UnitPoint = .center, lifts: Bool = true) -> some View {
        modifier(HoverZoom(scale: scale, anchor: anchor, lifts: lifts))
    }
}
