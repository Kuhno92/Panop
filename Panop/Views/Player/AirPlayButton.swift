#if !os(tvOS)
    import AVKit
    import SwiftUI

    /// The system's AirPlay route picker. It lists the speakers and screens nearby and the
    /// system does the rest, so nothing here knows about any destination.
    struct AirPlayButton {}

    #if os(macOS)
        extension AirPlayButton: NSViewRepresentable {
            func makeNSView(context: Context) -> AVRoutePickerView {
                let picker = AVRoutePickerView()
                picker.isRoutePickerButtonBordered = false
                return picker
            }

            func updateNSView(_ picker: AVRoutePickerView, context: Context) {}
        }
    #else
        extension AirPlayButton: UIViewRepresentable {
            func makeUIView(context: Context) -> AVRoutePickerView {
                let picker = AVRoutePickerView()
                picker.tintColor = .white
                picker.activeTintColor = .systemBlue
                // Video, not just audio, goes to a screen.
                picker.prioritizesVideoDevices = true
                return picker
            }

            func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
        }
    #endif
#endif
