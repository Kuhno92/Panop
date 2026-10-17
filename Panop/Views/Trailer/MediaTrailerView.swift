import AVKit
import SwiftUI

/// A trailer that is a video file or a stream: played by the system player, with its own controls.
struct MediaTrailerView: View {
    let url: URL
    var onFailure: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) {
            let item = AVPlayerItem(url: url)
            let made = AVPlayer(playerItem: item)
            player = made
            TrailerAudio.activate()
            made.play()
            // A file that cannot be opened ends here instead of showing a player with nothing in it.
            for await status in item.publisher(for: \.status).values where status == .failed {
                onFailure()
                return
            }
        }
        .onDisappear { player?.pause() }
    }
}

/// A trailer is meant to be heard, also with the ring switch on silent, like any video.
enum TrailerAudio {
    static func activate() {
        #if os(iOS) || os(tvOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}
