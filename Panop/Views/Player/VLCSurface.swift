import SwiftUI

/// Shows a VLC engine's video view in SwiftUI.
///
/// The view is owned by the engine, not created here: the engine needs to know when it
/// enters a window (libVLC must not draw before then), and there is exactly one per
/// engine instance. So this only hands that view to SwiftUI.
struct VLCSurface {
    let view: PlatformView
}

#if os(macOS)
    import AppKit

    extension VLCSurface: NSViewRepresentable {
        func makeNSView(context: Context) -> PlatformView {
            view
        }

        func updateNSView(_ view: PlatformView, context: Context) {}
    }
#else
    import UIKit

    extension VLCSurface: UIViewRepresentable {
        func makeUIView(context: Context) -> PlatformView {
            view
        }

        func updateUIView(_ view: PlatformView, context: Context) {}
    }
#endif
