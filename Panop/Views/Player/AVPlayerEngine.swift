import AVFoundation
import Foundation
import PanopCore

#if !os(tvOS)
    import AVKit
#endif
import PanopPlayback

/// The AVPlayer engine adapter.
///
/// **It reports; it does not decide.** No retry, no backoff, no fallback: those
/// belong to `PlaybackCoordinator` (see docs/adr/0002). What it does own is
/// translating AVFoundation's errors into `PlaybackError`, because the coordinator
/// acts on the code. The one that matters most: AVPlayer cannot read a raw
/// MPEG-TS stream and says so as "file format not recognized", which must
/// surface as `.unsupportedFormat` so the coordinator tries another engine
/// instead of retrying this one.
@MainActor
final class AVPlayerEngine: PlaybackEngine {
    static var kind: PlaybackEngineKind {
        .avPlayer
    }

    /// The player, for the video surface to draw.
    let player = AVPlayer()

    let events: AsyncStream<PlaybackEvent>
    private let output: AsyncStream<PlaybackEvent>.Continuation

    private(set) var state = PlaybackState.idle
    private(set) var audioTracks: [TrackDescriptor] = []
    private(set) var subtitleTracks: [TrackDescriptor] = []

    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var observers: [NSObjectProtocol] = []
    private var kvoTokens: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var wantsPlayback = false
    #if !os(tvOS)
        private var pictureInPicture: AVPictureInPictureController?
    #endif

    init() {
        (events, output) = AsyncStream.makeStream()
        #if !os(tvOS)
            // The default on iOS, and stated here because the AirPlay button in the
            // controls is pointless without it. The route is chosen by the user, never by us.
            player.allowsExternalPlayback = true
        #endif
    }

    // MARK: - Picture in Picture

    /// Whether this engine can float its video in a small window. Only AVPlayer can:
    /// the system's PiP needs an `AVPlayerLayer`, which the other engines do not draw
    /// into. Not on tvOS, which has no such window.
    var supportsPictureInPicture: Bool {
        #if os(tvOS)
            false
        #else
            pictureInPicture != nil
        #endif
    }

    /// Called once the view that draws the video exists, because PiP is made from its layer.
    func attach(layer: AVPlayerLayer) {
        #if !os(tvOS)
            guard pictureInPicture == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
            pictureInPicture = AVPictureInPictureController(playerLayer: layer)
        #endif
    }

    func togglePictureInPicture() {
        #if !os(tvOS)
            guard let pictureInPicture else { return }
            if pictureInPicture.isPictureInPictureActive {
                pictureInPicture.stopPictureInPicture()
            } else {
                pictureInPicture.startPictureInPicture()
            }
        #endif
    }

    var position: Double? {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : nil
    }

    var duration: Double? {
        guard let item = player.currentItem, item.duration.isNumeric else { return nil }
        let seconds = item.duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    // MARK: - Loading

    func load(_ item: PlaybackItem) async throws {
        guard let url = URL(string: item.url), url.scheme != nil else {
            throw PlaybackError(code: .invalidAddress, message: "That is not a valid stream address.")
        }
        setState(.opening)

        // Some providers reject requests without their expected User-Agent or Referer.
        var headers = item.headers
        if let userAgent = item.userAgent {
            headers["User-Agent"] = userAgent
        }
        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }

        let asset = AVURLAsset(url: url, options: options)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        try await waitUntilReady(playerItem)

        // Passed at load, not applied as a seek on a running stream: seeking an
        // in-flight IPTV connection makes some providers drop it.
        if let start = item.startPosition, start > 0 {
            await player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }

        startObserving(playerItem)
        await loadTracks(asset)
        setState(.buffering)
        output.yield(.ready(duration: duration))
    }

    /// Returns when the item can play, or throws what went wrong.
    private func waitUntilReady(_ item: AVPlayerItem) async throws {
        let statuses = AsyncStream<AVPlayerItem.Status> { continuation in
            let token = item.observe(\.status, options: [.initial, .new]) { observed, _ in
                continuation.yield(observed.status)
            }
            continuation.onTermination = { _ in token.invalidate() }
        }
        for await status in statuses {
            switch status {
            case .readyToPlay: return
            case .failed: throw Self.map(item.error)
            default: continue
            }
        }
        // The stream ends only on cancellation.
        throw CancellationError()
    }

    // MARK: - Observing

    private func startObserving(_ item: AVPlayerItem) {
        stopObserving()

        kvoTokens.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            MainActor.assumeIsolated { self?.timeControlChanged(status) }
        })
        kvoTokens.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = Self.map(item.error)
            MainActor.assumeIsolated { self?.report(failure: error) }
        })

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnd() }
        })
        observers.append(center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = Self.map(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            MainActor.assumeIsolated { self?.report(failure: error) }
        })
        observers.append(center.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didStall() }
        })

        // One tick a second is plenty for a scrubber and cheap enough not to
        // hitch playback.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                guard seconds.isFinite, self?.state == .playing else { return }
                self?.output.yield(.positionChanged(seconds: seconds))
            }
        }
    }

    private func stopObserving() {
        kvoTokens.forEach { $0.invalidate() }
        kvoTokens = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            setState(.playing)
        case .waitingToPlayAtSpecifiedRate:
            if wantsPlayback {
                setState(.buffering)
            }
        case .paused:
            // Also the state before `play()`; only a paused stream the user
            // asked to play is news.
            if wantsPlayback == false, state != .idle, state != .opening {
                setState(.paused)
            }
        @unknown default:
            break
        }
    }

    private func didEnd() {
        setState(.ended)
        output.yield(.ended)
    }

    private func didStall() {
        output.yield(.stalled(seconds: position ?? 0))
    }

    private func report(failure error: PlaybackError) {
        guard state != .failed else { return }
        setState(.failed)
        output.yield(.failed(error))
    }

    private func setState(_ new: PlaybackState) {
        guard new != state else { return }
        state = new
        output.yield(.stateChanged(new))
    }

    // MARK: - Controls

    func play() {
        wantsPlayback = true
        player.play()
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        setState(.paused)
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func selectAudioTrack(id: String?) {
        select(id, in: audioGroup)
    }

    func selectSubtitleTrack(id: String?) {
        select(id, in: subtitleGroup)
    }

    private func select(_ id: String?, in group: AVMediaSelectionGroup?) {
        guard let group, let item = player.currentItem else { return }
        guard let id, let index = Int(id), group.options.indices.contains(index) else {
            // Nil turns the group off, which only subtitles allow.
            if group.allowsEmptySelection {
                item.select(nil, in: group)
            }
            return
        }
        item.select(group.options[index], in: group)
    }

    func stop() async {
        stopObserving()
        wantsPlayback = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
        output.finish()
    }

    // MARK: - Tracks

    private func loadTracks(_ asset: AVAsset) async {
        audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
        subtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        audioTracks = Self.descriptors(audioGroup)
        subtitleTracks = Self.descriptors(subtitleGroup)
        output.yield(.tracksChanged(audio: audioTracks, subtitle: subtitleTracks))
    }

    nonisolated static func descriptors(_ group: AVMediaSelectionGroup?) -> [TrackDescriptor] {
        (group?.options ?? []).enumerated().map { index, option in
            TrackDescriptor(
                id: String(index),
                label: option.displayName,
                languageCode: option.locale?.language.languageCode?.identifier,
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            )
        }
    }

    // MARK: - Errors

    /// Translates AVFoundation's errors into what the coordinator acts on.
    ///
    /// The rule is deliberately the reverse of a list of known format codes.
    /// AVFoundation reports an unreadable stream with a different code per
    /// container (measured: -11829 for a malformed MP4, -11828 for MKV, and an
    /// unnamed -11849 for MP3 and transport streams), so a list is always one
    /// code behind. Instead, anything AVFoundation reports that is not clearly a
    /// network, authorization or decode problem means "AVPlayer cannot make
    /// sense of these bytes", and the answer is the next engine, at once.
    ///
    /// Being wrong is cheap in the direction this errs: a transient server
    /// error read as a format problem just plays on another engine. The
    /// opposite mistake, retrying a format AVPlayer can never read, makes the
    /// user wait.
    nonisolated static func map(_ error: Error?) -> PlaybackError {
        guard let error = error as NSError? else {
            return PlaybackError(code: .internalError, message: "Playback failed for an unknown reason.")
        }
        let message = error.localizedDescription

        if let network = networkError(error) {
            return PlaybackError(code: .network, message: network)
        }

        guard error.domain == AVFoundationErrorDomain else {
            return PlaybackError(code: .openFailed, message: message)
        }
        switch AVError.Code(rawValue: error.code) {
        case .undecodableMediaData, .decoderTemporarilyUnavailable:
            return PlaybackError(code: .decodeFailed, message: message)
        case .contentIsNotAuthorized, .applicationIsNotAuthorized:
            return PlaybackError(code: .openFailed, message: message)
        case .sessionNotRunning:
            return PlaybackError(code: .internalError, message: message)
        default:
            return PlaybackError(code: .unsupportedFormat, message: message)
        }
    }

    /// A network failure anywhere in the error chain, since AVFoundation wraps
    /// the real cause in its own error.
    nonisolated static func networkError(_ error: NSError) -> String? {
        var current: NSError? = error
        while let next = current {
            if next.domain == NSURLErrorDomain {
                return next.localizedDescription
            }
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }
}
