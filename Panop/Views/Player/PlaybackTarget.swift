import Foundation
import PanopCore
import PanopPlayback
import PanopXtream

/// What the user chose to play, as plain values.
///
/// A snapshot rather than the model object, so the player does not hold a live
/// SwiftData record while it runs, and so a request can be built off the main actor.
nonisolated struct PlaybackTarget: Identifiable, Equatable, Sendable {
    var playlist: String
    var entryID: String
    var kind: MediaKind
    var name: String
    /// A complete URL when the source gave one (M3U, or an Xtream `direct_source`).
    var streamURL: String?
    /// The provider's own id, for building an Xtream URL.
    var remoteID: String?
    var containerExtension: String?

    var id: String {
        "\(playlist)|\(entryID)"
    }
}

nonisolated enum PlaybackTargetError: Error, Equatable {
    /// Explains why this cannot be played, in words for the user.
    case notPlayable(String)

    var message: String {
        switch self {
        case let .notPlayable(text): text
        }
    }
}

nonisolated enum PlaybackRequestBuilder {
    /// Builds the request for a target.
    ///
    /// The address depends on the engine that will play it. An Xtream live channel
    /// is offered as HLS to AVPlayer, which cannot read a raw transport stream, and
    /// as a plain `.ts` stream to the FFmpeg-based engines, which read that
    /// directly and with less delay.
    static func request(
        for target: PlaybackTarget,
        source: PlaylistSource?,
        transport: any HTTPTransport
    ) throws -> PlaybackRequest {
        if let url = target.streamURL, !url.isEmpty {
            let item = PlaybackItem(url: url, title: target.name, mediaKind: target.kind)
            return PlaybackRequest(mediaKind: target.kind) { _ in item }
        }

        guard case let .xtream(credentials)? = source else {
            throw PlaybackTargetError
                .notPlayable("This item has no stream address. Refresh the playlist and try again.")
        }
        guard let remote = target.remoteID.flatMap(Int.init) else {
            throw PlaybackTargetError
                .notPlayable("This item is missing its provider id. Refresh the playlist and try again.")
        }
        let client: XtreamClient
        do {
            client = try XtreamClient(credentials: credentials, transport: transport)
        } catch {
            throw PlaybackTargetError.notPlayable("The provider's server address is not valid.")
        }

        switch target.kind {
        case .live:
            return PlaybackRequest(mediaKind: .live) { engine in
                let format: XtreamClient.LiveFormat = engine == .avPlayer ? .hls : .transportStream
                return PlaybackItem(
                    url: client.liveURL(streamID: remote, format: format)?.absoluteString ?? "",
                    title: target.name,
                    mediaKind: .live
                )
            }
        case .movie:
            let ext = target.containerExtension
            return PlaybackRequest(mediaKind: .movie) { _ in
                PlaybackItem(
                    url: client.movieURL(streamID: remote, containerExtension: ext)?.absoluteString ?? "",
                    title: target.name,
                    mediaKind: .movie
                )
            }
        case .series, .unknown:
            throw PlaybackTargetError.notPlayable("Open the series to pick an episode.")
        }
    }
}
