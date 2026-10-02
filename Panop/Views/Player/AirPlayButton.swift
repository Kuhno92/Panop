#if !os(tvOS)
    import AVKit
    import SwiftUI

    /// The system's AirPlay route picker. It lists the speakers and screens nearby and the
    /// system does the rest, so nothing here knows about any destination.
    struct AirPlayButton {
        /// Told when the route picker opens and closes, so the controls can stay up behind it.
        var onPresenting: (Bool) -> Void = { _ in }

        /// The picker has no way of saying it is open except through its delegate.
        final class Coordinator: NSObject, AVRoutePickerViewDelegate {
            var onPresenting: (Bool) -> Void

            init(_ onPresenting: @escaping (Bool) -> Void) {
                self.onPresenting = onPresenting
            }

            func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
                onPresenting(true)
            }

            func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
                onPresenting(false)
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onPresenting)
        }
    }

    #if os(macOS)
        extension AirPlayButton: NSViewRepresentable {
            func makeNSView(context: Context) -> AVRoutePickerView {
                let picker = AVRoutePickerView()
                picker.isRoutePickerButtonBordered = false
                picker.delegate = context.coordinator
                return picker
            }

            func updateNSView(_ picker: AVRoutePickerView, context: Context) {
                context.coordinator.onPresenting = onPresenting
            }
        }
    #else
        extension AirPlayButton: UIViewRepresentable {
            func makeUIView(context: Context) -> AVRoutePickerView {
                let picker = AVRoutePickerView()
                picker.tintColor = .white
                picker.activeTintColor = .systemBlue
                // Video, not just audio, goes to a screen.
                picker.prioritizesVideoDevices = true
                picker.delegate = context.coordinator
                return picker
            }

            func updateUIView(_ picker: AVRoutePickerView, context: Context) {
                context.coordinator.onPresenting = onPresenting
            }
        }
    #endif
#endif
