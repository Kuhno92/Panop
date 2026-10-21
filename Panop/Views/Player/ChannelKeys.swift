#if os(macOS)
    import AppKit
    import SwiftUI

    /// Up and Down switch to the previous and the next channel on a Mac, as they do on the Apple TV remote.
    ///
    /// A key monitor on the window rather than `onKeyPress`: the arrows must work without the picture holding keyboard
    /// focus, which a click on a control, a closed sheet or the main window's own lists keep taking away. It steps
    /// aside
    /// whenever the arrows mean something else: while a text field is being edited, while a sheet is open over the
    /// window (the guide, the stream details), with a modifier held, and while `isEnabled` is false (the player is
    /// behind the app, or the stream is not a channel).
    struct ChannelKeys: NSViewRepresentable {
        let isEnabled: Bool
        let onStep: (Int) -> Void

        func makeNSView(context: Context) -> KeyView {
            KeyView()
        }

        func updateNSView(_ view: KeyView, context: Context) {
            view.isEnabled = isEnabled
            view.onStep = onStep
        }

        static func dismantleNSView(_ view: KeyView, coordinator: ()) {
            view.removeMonitor()
        }

        final class KeyView: NSView {
            var isEnabled = false
            var onStep: (Int) -> Void = { _ in }
            private var monitor: Any?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                removeMonitor()
                guard window != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let step = step(for: event) else { return event }
                    MainActor.assumeIsolated { self.onStep(step) }
                    return nil
                }
            }

            func removeMonitor() {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }

            /// -1 for Up, 1 for Down, nil where the key is not ours to take.
            private func step(for event: NSEvent) -> Int? {
                guard isEnabled, let window, event.window === window, window.isKeyWindow, window.attachedSheet == nil,
                      event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
                      !(window.firstResponder is NSText)
                else { return nil }
                switch event.keyCode {
                case 126: return -1 // Up arrow
                case 125: return 1 // Down arrow
                default: return nil
                }
            }
        }
    }
#endif
