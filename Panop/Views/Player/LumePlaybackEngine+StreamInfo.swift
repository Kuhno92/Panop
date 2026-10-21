import LumeEngine
import PanopPlayback

extension LumePlaybackEngine {
    /// From what the demuxer found: the first video stream and the audio stream that plays.
    var streamInfo: StreamInfo? {
        guard let media = mediaInfo else { return nil }
        let video = media.videoTracks.first
        let audio = chosenAudioIndex.flatMap { index in media.audioTracks.first { $0.index == index } }
            ?? media.audioTracks.first { $0.isDefault } ?? media.audioTracks.first
        return StreamInfo(
            container: media.formatName,
            videoCodec: video?.codecName,
            width: video?.video?.width,
            height: video?.video?.height,
            frameRate: video?.video.flatMap { $0.fps > 0 ? $0.fps : nil },
            hdr: video?.video.flatMap(Self.hdrName),
            audioCodec: audio?.codecName,
            audioChannels: audio?.audio?.channels
        )
    }

    /// The transfer characteristic says which kind of HDR: 16 is PQ (HDR10 or Dolby Vision), 18 is HLG.
    private static func hdrName(_ video: TrackInfo.Video) -> String? {
        guard video.isHDR else { return nil }
        return switch video.colorTransfer {
        case 16: "HDR10"
        case 18: "HLG"
        default: "HDR"
        }
    }
}
