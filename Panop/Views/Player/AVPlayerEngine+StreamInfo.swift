import AVFoundation
import CoreMedia
import PanopPlayback

extension AVPlayerEngine {
    /// From the tracks AVPlayer enabled; the size is the one on screen, which for an adaptive stream is the
    /// rendition it is playing now.
    var streamInfo: StreamInfo? {
        guard let item = player.currentItem, item.status == .readyToPlay else { return nil }
        var info = StreamInfo()
        for track in item.tracks where track.isEnabled {
            // A CoreFoundation type: the cast cannot fail once the array holds format descriptions.
            guard let asset = track.assetTrack,
                  let format = asset.formatDescriptions.first
                  .map({ $0 as! CMFormatDescription }) // swiftlint:disable:this force_cast
            else { continue }
            switch asset.mediaType {
            case .video:
                StreamInfoReader.fill(&info, video: format, frameRate: Double(track.currentVideoFrameRate))
            case .audio where info.audioCodec == nil:
                StreamInfoReader.fill(&info, audio: format)
            default:
                break
            }
        }
        let size = item.presentationSize
        if size.width > 0, size.height > 0 {
            info.width = Int(size.width)
            info.height = Int(size.height)
        }
        return info.isEmpty ? nil : info
    }
}
