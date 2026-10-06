import Foundation
import KSPlayerBridge
import PanopCore
import PanopPlayback

/// The KSPlayer adapter. KSPlayer is GPL-3.0, so linking it makes Panop's binary GPL-3.0 (LICENSE,
/// THIRD-PARTY-NOTICES.md). It plays through its own FFmpeg, with hardware decoding where the machine has it.
///
/// KSPlayer is reached only through `KSPlayerBridge`, a package that keeps KSPlayer's FFmpeg modules out of the
/// app's compile, where they would collide with AetherEngine's and LumeEngine's (Packages/KSPlayerBridge).
///
/// **It reports; it does not decide.** No retry, no backoff, no fallback (docs/adr/0002). KSPlayer tells us
/// when it is ready, loading, finished or failed; those become the coordinator's events.
///
/// One engine plays one item, as with every adapter: a channel change is a new engine.
@MainActor
final class KSPlayerEngine: PlaybackEngine {
    static var kind: PlaybackEngineKind {
        .ksPlayer
    }

    /// What the video is drawn into: KSPlayer owns the view, SwiftUI is only handed this container (`VLCSurface`).
    let surface = PlatformView()
    /// KSPlayer parses subtitles but leaves drawing to the app; the player overlay draws this.
    let subtitles = SubtitleDisplay()

    let events: AsyncStream<PlaybackEvent>
    private let output: AsyncStream<PlaybackEvent>.Continuation

    private(set) var state = EngineState.idle
    private(set) var position: Double?
    private(set) var duration: Double?
    private(set) var audioTracks: [TrackDescriptor] = []
    private(set) var subtitleTracks: [TrackDescriptor] = []

    private var bridge: KSBridge?
    private var ticker: Task<Void, Never>?
    private var isLive = false
    private var isStopping = false
    private var hasPlayed = false
    private var lastPositionReport = -1.0

    init() {
        (events, output) = AsyncStream.makeStream()
    }

    // MARK: - Loading

    func load(_ item: PlaybackItem) async throws {
        guard let url = URL(string: item.url), url.scheme != nil else {
            throw PlaybackError(code: .invalidAddress, message: "That is not a valid stream address.")
        }
        isLive = item.mediaKind == .live

        // `User-Agent` and `Referer` have their own settings; anything else rides in FFmpeg's header block.
        var extra = item.headers
        let referer = extra.removeValue(forKey: "Referer")
        let agent = extra.removeValue(forKey: "User-Agent") ?? item.userAgent

        let bridge = KSBridge(
            url: url, userAgent: agent, referer: referer, headers: extra,
            startAt: item.startPosition, isLive: isLive
        )
        bridge.onReady = { [weak self] in self?.readyToPlay() }
        bridge.onLoadChanged = { [weak self] in self?.loadStateChanged() }
        bridge.onFinished = { [weak self] failure in self?.finished(failure) }
        self.bridge = bridge
        install(bridge.view)

        setState(.opening)
        bridge.start()
        startTicker()
    }

    /// KSPlayer's video view fills the surface and follows its size.
    private func install(_ video: PlatformView) {
        surface.subviews.forEach { $0.removeFromSuperview() }
        video.frame = surface.bounds
        #if os(macOS)
            video.autoresizingMask = [.width, .height]
        #else
            video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
        surface.addSubview(video)
    }

    // MARK: - Controls

    func play() {
        bridge?.play()
        if hasPlayed {
            setState(.playing)
        }
    }

    func pause() {
        bridge?.pause()
        setState(.paused)
    }

    func seek(to seconds: Double) {
        bridge?.seek(to: seconds)
    }

    func selectAudioTrack(id: String?) {
        guard let id = id.flatMap({ Int32($0) }) else { return }
        bridge?.selectAudio(id: id)
        refreshTracks()
    }

    func selectSubtitleTrack(id: String?) {
        bridge?.selectSubtitle(id: id.flatMap { Int32($0) })
        if id == nil {
            subtitles.set(nil)
        }
        refreshTracks()
    }

    func stop() async {
        isStopping = true
        ticker?.cancel()
        subtitles.set(nil)
        bridge?.shutdown()
        bridge = nil
        state = .idle
        output.finish()
    }

    // MARK: - What the engine reports

    private func readyToPlay() {
        guard !isStopping, let bridge else { return }
        duration = isLive || bridge.duration <= 0 ? nil : bridge.duration
        refreshTracks()
    }

    private func loadStateChanged() {
        guard !isStopping, let bridge else { return }
        switch bridge.loadState {
        case .loading:
            setState(hasPlayed ? .buffering : .opening)
        case .playable:
            if !hasPlayed {
                hasPlayed = true
                duration = isLive || bridge.duration <= 0 ? nil : bridge.duration
                refreshTracks()
                output.yield(.ready(duration: duration))
                output.yield(.tracksChanged(audio: audioTracks, subtitle: subtitleTracks))
            }
            setState(bridge.isPaused ? .paused : .playing)
        case .idle:
            break
        @unknown default:
            break
        }
    }

    private func finished(_ failure: KSBridgeFailure?) {
        guard !isStopping else { return }
        if let failure {
            setState(.failed)
            output.yield(.failed(Self.map(failure)))
        } else {
            setState(.ended)
            output.yield(.ended)
        }
    }

    /// Position and the subtitle line, a few times a second: KSPlayer has no callback for either.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard !isStopping, let bridge else { return }
        let seconds = bridge.currentTime
        position = seconds
        if state == .playing, seconds.rounded(.down) != lastPositionReport {
            lastPositionReport = seconds.rounded(.down)
            output.yield(.positionChanged(seconds: seconds))
        }
        subtitles.set(bridge.subtitleText(at: seconds))
    }

    private func refreshTracks() {
        guard let bridge else { return }
        audioTracks = bridge.audioTracks.map(Self.descriptor)
        subtitleTracks = bridge.subtitleTracks.filter { !$0.isImage }.map(Self.descriptor)
        if hasPlayed {
            output.yield(.tracksChanged(audio: audioTracks, subtitle: subtitleTracks))
        }
    }

    private func setState(_ new: EngineState) {
        guard new != state else { return }
        state = new
        output.yield(.stateChanged(new))
    }

    // MARK: - Translation

    nonisolated static func descriptor(_ track: KSBridgeTrack) -> TrackDescriptor {
        TrackDescriptor(
            id: String(track.id),
            label: track.name.isEmpty ? (track.languageCode ?? "Track \(track.id)") : track.name,
            languageCode: track.languageCode,
            isForced: false
        )
    }

    nonisolated static func map(_ failure: KSBridgeFailure) -> PlaybackError {
        // What FFmpeg could not open or decode is reported as a failure to open; the coordinator tries another
        // engine.
        failure.domain == NSURLErrorDomain
            ? PlaybackError(code: .network, message: failure.message)
            : PlaybackError(code: .openFailed, message: failure.message)
    }
}
