import AVFoundation
import SwiftUI

/// Draws an `AVPlayer`'s video. A bare `AVPlayerLayer`, not AVKit's player view:
/// Panop draws its own overlay so it looks the same whichever engine is playing.
struct AVPlayerSurface {
    let player: AVPlayer
    /// Told about the layer once it exists, for Picture in Picture.
    var onLayer: ((AVPlayerLayer) -> Void)?
}

#if os(macOS)
    import AppKit

    extension AVPlayerSurface: NSViewRepresentable {
        func makeNSView(context: Context) -> PlayerLayerView {
            let view = PlayerLayerView()
            view.playerLayer.player = player
            onLayer?(view.playerLayer)
            return view
        }

        func updateNSView(_ view: PlayerLayerView, context: Context) {
            if view.playerLayer.player !== player {
                view.playerLayer.player = player
            }
        }
    }

    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = playerLayer
            playerLayer.videoGravity = .resizeAspect
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }
    }
#else
    import UIKit

    extension AVPlayerSurface: UIViewRepresentable {
        func makeUIView(context: Context) -> PlayerLayerView {
            let view = PlayerLayerView()
            view.playerLayer.player = player
            onLayer?(view.playerLayer)
            return view
        }

        func updateUIView(_ view: PlayerLayerView, context: Context) {
            if view.playerLayer.player !== player {
                view.playerLayer.player = player
            }
        }
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            // The layer class is fixed above, so the cast cannot fail.
            // swiftlint:disable:next force_cast
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }
    }
#endif
