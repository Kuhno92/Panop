import Foundation
import PanopCore
import PanopPlayback
import PanopXtream

/// What the user chose to play, as plain values.
///
/// A snapshot rather than the model object, so the player does not hold a live
/// SwiftData record while it runs, and so a request can be built off the main actor.
nonisolated struct PlaybackTarget: Identifiable, Equatable, Hashable, Sendable {
    var playlist: String
    var entryID: String
    var kind: MediaKind
    var name: String
    /// A complete URL when the source gave one (M3U, or an Xtream `direct_source`).
    var streamURL: String?
    /// The provider's own id, for building an Xtream URL.
    var remoteID: String?
    var containerExtension: String?
    /// Where to start, in seconds, for a film or episode someone left part-way. Passed at load
    /// time, not applied by seeking afterwards: seeking a running connection makes some
    /// providers drop it.
    var resumeAt: Double?

    var id: String {
        "\(playlist)|\(entryID)"
    }
}

/// What a macOS player window is opened with.
///
/// **No stream address.** A window's value is saved by the system to restore it later, and an
/// address can carry the account's login. So this holds only which item it is, and the window
/// looks the address up again: from the catalog for a channel or film, or from the playlist's
/// own login for an episode.
nonisolated struct PlayerWindowRequest: Codable, Hashable {
    var playlist: String
    var entryID: String
    var kind: MediaKind
    var name: String
    /// For an episode, its id, from which its address is rebuilt.
    var remoteID: String?
    var containerExtension: String?
    var resumeAt: Double?

    init(_ target: PlaybackTarget) {
        playlist = target.playlist
        entryID = target.entryID
        kind = target.kind
        name = target.name
        remoteID = target.remoteID
        containerExtension = target.containerExtension
        resumeAt = target.resumeAt
    }

    /// The target to play, given the address if the catalog has one for this item.
    func target(streamURL: String?) -> PlaybackTarget {
        PlaybackTarget(
            playlist: playlist,
            entryID: entryID,
            kind: kind,
            name: name,
            streamURL: streamURL,
            remoteID: remoteID,
            containerExtension: containerExtension,
            resumeAt: resumeAt
        )
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
            // A path with no scheme and host reaches an engine as a failure that
            // looks like a network problem. Say what is wrong instead.
            guard let parsed = URL(string: url), parsed.scheme != nil,
                  parsed.isFileURL || parsed.host?.isEmpty == false || url.contains("://@")
            else {
                throw PlaybackTargetError
                    .notPlayable("This item's address is incomplete. Refresh the playlist and try again.")
            }
            let item = PlaybackItem(
                url: url,
                title: target.name,
                startPosition: target.kind == .live ? nil : target.resumeAt,
                mediaKind: target.kind
            )
            return PlaybackRequest(mediaKind: target.kind) { _ in item }
        }

        guard case let .xtream(credentials)? = source else {
            throw PlaybackTargetError
                .notPlayable("This item has no stream address. Refresh the playlist and try again.")
        }
        // An episode is not a catalog row: its address is built from the playlist's login and the
        // episode's own id, which is a string on some panels and so is not parsed as a number.
        // Told apart by its id, not by having a provider id: a series *shell* in the catalog has
        // one too, and is not playable (below).
        if target.kind == .series, target.entryID.hasPrefix("episode:"), let episodeID = target.remoteID,
           !episodeID.isEmpty
        {
            let client: XtreamClient
            do {
                client = try XtreamClient(credentials: credentials, transport: transport)
            } catch {
                throw PlaybackTargetError.notPlayable("The provider's server address is not valid.")
            }
            let ext = target.containerExtension
            let resume = target.resumeAt
            return PlaybackRequest(mediaKind: .series) { _ in
                PlaybackItem(
                    url: client.episodeURL(episodeID: episodeID, containerExtension: ext)?.absoluteString ?? "",
                    title: target.name,
                    startPosition: resume,
                    mediaKind: .series
                )
            }
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
            let resume = target.resumeAt
            return PlaybackRequest(mediaKind: .movie) { _ in
                PlaybackItem(
                    url: client.movieURL(streamID: remote, containerExtension: ext)?.absoluteString ?? "",
                    title: target.name,
                    startPosition: resume,
                    mediaKind: .movie
                )
            }
        case .series, .unknown:
            throw PlaybackTargetError.notPlayable("Open the series to pick an episode.")
        }
    }
}
