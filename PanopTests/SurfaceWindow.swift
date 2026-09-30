import Foundation
@testable import Panop
import PanopPlayback

#if os(macOS)
    import AppKit

    /// Puts an engine's video surface in a real window, as the app does. libVLC's video
    /// output needs a view that is on screen; a detached one crashes it.
    @MainActor
    final class SurfaceWindow {
        private let window: NSWindow

        init(_ surface: PlatformView, size: CGSize = CGSize(width: 320, height: 180)) {
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            // AppKit windows release themselves on close by default, which would
            // over-release one that Swift also owns.
            window.isReleasedWhenClosed = false
            window.contentView = surface
            window.orderFrontRegardless()
        }

        func close() {
            window.close()
        }

        /// Takes the surface off screen, leaving the window.
        func detach() {
            window.contentView = NSView()
        }
    }
#else
    import UIKit

    @MainActor
    final class SurfaceWindow {
        private let window: UIWindow

        init(_ surface: PlatformView, size: CGSize = CGSize(width: 320, height: 180)) {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
            let controller = UIViewController()
            window.rootViewController = controller
            surface.frame = CGRect(origin: .zero, size: size)
            controller.view.addSubview(surface)
            window.isHidden = false
        }

        func close() {
            window.isHidden = true
        }

        func detach() {
            window.rootViewController?.view.subviews.forEach { $0.removeFromSuperview() }
        }
    }
#endif

/// Puts the surface of every VLC engine a coordinator creates on screen, as the app's
/// player view does. The coordinator makes its own engines, so a test cannot attach
/// them by hand.
@MainActor
final class SurfaceAttacher {
    private var windows: [SurfaceWindow] = []
    private var task: Task<Void, Never>?

    init(_ coordinator: PlaybackCoordinator) {
        task = Task { [weak self] in
            var seen: ObjectIdentifier?
            while !Task.isCancelled {
                if let engine = coordinator.activeEngine as? VLCEngine, seen != ObjectIdentifier(engine) {
                    seen = ObjectIdentifier(engine)
                    self?.windows.append(SurfaceWindow(engine.surface))
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        windows.forEach { $0.close() }
    }
}
