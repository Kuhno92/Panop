#if os(tvOS)
    import AVKit
    import SwiftUI
    import YouTubeKit

    /// A YouTube trailer on an Apple TV, which has no web view: the video and its sound are read from YouTube's own
    /// page data
    /// and played by the system player. This is not YouTube's player, and YouTube's terms allow only its own; it is
    /// here
    /// because the owner chose it for Apple TV, and it may stop working whenever YouTube changes its page.
    ///
    /// Only the device asks YouTube: no helper server is used (the library's remote fallback is left off), so no one
    /// else is
    /// told which trailer is watched.
    struct ExtractedYouTubeTrailer: View {
        let videoID: String
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
            .task(id: videoID) { await load() }
            .onDisappear { player?.pause() }
        }

        private func load() async {
            do {
                guard let found = try await TrailerStreamFinder.addresses(for: videoID) else {
                    onFailure()
                    return
                }
                let item = try await Self.item(for: found)
                TrailerAudio.activate()
                let made = AVPlayer(playerItem: item)
                player = made
                made.play()
            } catch {
                onFailure()
            }
        }

        /// One item to play: the stream itself when YouTube gives picture and sound together, else the best picture and
        /// the
        /// best sound laid side by side in one composition.
        private static let headers: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "Mozilla/5.0"]]

        private static func item(for found: TrailerStreamAddresses) async throws -> AVPlayerItem {
            guard let audioAddress = found.audio else { return AVPlayerItem(url: found.video) }
            let video = AVURLAsset(url: found.video, options: Self.headers)
            let audio = AVURLAsset(url: audioAddress, options: Self.headers)
            async let videoTracks = video.loadTracks(withMediaType: .video)
            async let audioTracks = audio.loadTracks(withMediaType: .audio)
            async let videoLength = video.load(.duration)
            guard let videoTrack = try await videoTracks.first, let audioTrack = try await audioTracks.first else {
                throw TrailerStreamError.noTracks
            }
            let length = try await videoLength
            let composition = AVMutableComposition()
            let range = CMTimeRange(start: .zero, duration: length)
            guard let pictureOut = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
                let soundOut = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            else { throw TrailerStreamError.noTracks }
            try pictureOut.insertTimeRange(range, of: videoTrack, at: .zero)
            try soundOut.insertTimeRange(range, of: audioTrack, at: .zero)
            return AVPlayerItem(asset: composition)
        }
    }

    enum TrailerStreamError: Error {
        case noTracks
    }

    /// Where a trailer's picture and sound are. When YouTube serves them as one stream, `audio` is nil.
    struct TrailerStreamAddresses: Sendable {
        var video: URL
        var audio: URL?
    }

    /// Reads the streams of a YouTube video. Off the main actor, because the library's objects are not for sharing
    /// between
    /// actors: only addresses come back.
    nonisolated enum TrailerStreamFinder {
        private static func size(_ url: URL) -> Int {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "clen" }?.value
                .flatMap(Int.init) ?? .max
        }

        /// The picture is the sharpest the system can play up to 1080 lines (more is more to download and to decode,
        /// for
        /// a trailer), the sound the best there is.
        static func addresses(for videoID: String) async throws -> TrailerStreamAddresses? {
            let youtube = YouTube(videoID: videoID, methods: [.local])
            // YouTube's playlist for the system player: picture and sound together, in the chunks its servers expect.
            // The
            // separate files below are fetched in one long request, which the servers throttle to a crawl.
            if let playlist = try? await youtube.livestreams.first {
                return TrailerStreamAddresses(video: playlist.url, audio: nil)
            }
            let streams = try await youtube.streams
            if let together = streams.filterVideoAndAudio().filter(\.isNativelyPlayable).highestResolutionStream() {
                return TrailerStreamAddresses(video: together.url, audio: nil)
            }
            let pictures = streams.filterVideoOnly().filter(\.isNativelyPlayable)
            let capped = pictures.filter { ($0.videoResolution ?? 0) <= 720 }
            let pool = capped.isEmpty ? pictures : capped
            let top = pool.compactMap(\.videoResolution).max()
            guard let picture = pool.filter({ $0.videoResolution == top })
                .min(by: { Self.size($0.url) < Self.size($1.url) }),
                let sound = streams.filterAudioOnly().filter(\.isNativelyPlayable).highestAudioBitrateStream()
            else { return nil }
            return TrailerStreamAddresses(video: picture.url, audio: sound.url)
        }
    }
#endif
