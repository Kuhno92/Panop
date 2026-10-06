import AVFoundation
import Foundation
import KSPlayer
#if canImport(UIKit)
    public import UIKit

    public typealias BridgeView = UIView
#else
    public import AppKit

    public typealias BridgeView = NSView
#endif

/// What KSPlayer is doing, in terms that name nothing of KSPlayer's.
public enum KSBridgeLoad: Sendable {
    case idle, loading, playable
}

public struct KSBridgeTrack: Sendable, Equatable {
    public var id: Int32
    public var name: String
    public var languageCode: String?
    public var isImage: Bool
    public var isEnabled: Bool
}

public struct KSBridgeFailure: Error, Sendable {
    public var domain: String
    public var code: Int
    public var message: String
}

/// One KSPlayer playback. Everything the app needs of KSPlayer, and nothing of its types.
@MainActor
public final class KSBridge {
    /// The video. KSPlayer owns it; the app puts it in a view.
    public let view: BridgeView

    public var onReady: (() -> Void)?
    public var onLoadChanged: (() -> Void)?
    /// Called when playback ends: nil for the end of the stream, else what went wrong.
    public var onFinished: ((KSBridgeFailure?) -> Void)?

    private let player: KSMEPlayer
    private let observer: Observer

    public init(
        url: URL, userAgent: String?, referer: String?, headers: [String: String],
        startAt: Double?, isLive: Bool
    ) {
        let options = KSOptions()
        if let userAgent {
            options.userAgent = userAgent
        }
        if let referer {
            options.referer = referer
        }
        if !headers.isEmpty {
            options.formatContextOptions["headers"] =
                headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n") + "\r\n"
        }
        if let startAt, startAt > 0 {
            options.startPlayTime = startAt
        }
        options.isSecondOpen = isLive
        KSOptions.logLevel = .warning
        player = KSMEPlayer(url: url, options: options)
        view = player.view ?? BridgeView()
        observer = Observer()
        observer.owner = self
        player.delegate = observer
    }

    public func start() {
        player.prepareToPlay()
        player.play()
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func seek(to seconds: Double) {
        player.seek(time: seconds) { _ in }
    }

    public var currentTime: Double {
        player.currentPlaybackTime
    }

    public var duration: Double {
        player.duration
    }

    public var loadState: KSBridgeLoad {
        switch player.loadState {
        case .idle: .idle
        case .loading: .loading
        case .playable: .playable
        }
    }

    public var isPaused: Bool {
        player.playbackState == .paused
    }

    public var audioTracks: [KSBridgeTrack] {
        Self.tracks(player.tracks(mediaType: .audio))
    }

    public var subtitleTracks: [KSBridgeTrack] {
        Self.tracks(player.tracks(mediaType: .subtitle))
    }

    public func selectAudio(id: Int32) {
        if let track = player.tracks(mediaType: .audio).first(where: { $0.trackID == id }) {
            player.select(track: track)
        }
    }

    /// Nil turns subtitles off.
    public func selectSubtitle(id: Int32?) {
        let tracks = player.tracks(mediaType: .subtitle)
        if let id, let track = tracks.first(where: { $0.trackID == id }) {
            player.select(track: track)
        } else {
            for track in tracks {
                track.isEnabled = false
            }
        }
    }

    /// The text of the enabled text subtitle at this moment. Picture subtitles are not returned.
    public func subtitleText(at seconds: Double) -> String? {
        let selected = player.tracks(mediaType: .subtitle).first { $0.isEnabled && !$0.isImageSubtitle }
        guard let info = selected as? any SubtitleInfo else { return nil }
        let text = info.search(for: seconds).compactMap { $0.text?.string }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    public func shutdown() {
        player.delegate = nil
        player.shutdown()
    }

    private static func tracks(_ tracks: [MediaPlayerTrack]) -> [KSBridgeTrack] {
        tracks.map {
            KSBridgeTrack(
                id: $0.trackID, name: $0.name, languageCode: $0.languageCode,
                isImage: $0.isImageSubtitle, isEnabled: $0.isEnabled
            )
        }
    }

    @MainActor
    private final class Observer: MediaPlayerDelegate {
        weak var owner: KSBridge?

        func readyToPlay(player _: some MediaPlayerProtocol) {
            owner?.onReady?()
        }

        func changeLoadState(player _: some MediaPlayerProtocol) {
            owner?.onLoadChanged?()
        }

        func changeBuffering(player _: some MediaPlayerProtocol, progress _: Int) {}

        func playBack(player _: some MediaPlayerProtocol, loopCount _: Int) {}

        func finish(player _: some MediaPlayerProtocol, error: Error?) {
            let failure = error.map {
                let nsError = $0 as NSError
                return KSBridgeFailure(domain: nsError.domain, code: nsError.code, message: $0.localizedDescription)
            }
            owner?.onFinished?(failure)
        }
    }
}
