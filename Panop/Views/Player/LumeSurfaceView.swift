import AVFoundation
import QuartzCore

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Hosts the layer LumeEngine draws into. The engine owns one of these for its whole
/// life and the layer arrives later, once `load` has made a session, so SwiftUI can
/// be handed a stable view before there is anything to show.
final class LumeSurfaceView: PlatformView {
    private weak var hosted: AVSampleBufferDisplayLayer?

    func install(layer: AVSampleBufferDisplayLayer) {
        layer.videoGravity = .resizeAspect
        guard hosted !== layer else { return }
        hosted?.removeFromSuperlayer()
        layer.frame = bounds
        #if os(macOS)
            wantsLayer = true
            self.layer?.addSublayer(layer)
        #else
            self.layer.addSublayer(layer)
        #endif
        hosted = layer
    }

    func removeLayer() {
        hosted?.removeFromSuperlayer()
        hosted = nil
    }

    private func fitLayer() {
        // Resizing a layer animates by default, which makes video swim during a resize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted?.frame = bounds
        CATransaction.commit()
    }

    #if os(macOS)
        override func layout() {
            super.layout()
            fitLayer()
        }
    #else
        override func layoutSubviews() {
            super.layoutSubviews()
            fitLayer()
        }
    #endif
}
