import AetherEngine

// swiftlint:disable:next duplicate_imports
import enum AetherEngine.PlaybackState
import Combine
import Foundation
import PanopCore
import PanopPlayback

/// Panop's own, since AetherEngine has a `PlaybackState` as well and the file imports that one by name.
typealias EngineState = PanopPlayback.PlaybackState

/// The AetherEngine adapter. LGPL-3.0 with an Apple Store exception, its FFmpeg frameworks linked dynamically
/// (see THIRD-PARTY-NOTICES.md and docs/engines.md).
///
/// **It reports; it does not decide.** No retry, no backoff, no fallback (docs/adr/0002): the engine's own
/// reconnecting is left to the coordinator above. What AetherEngine publishes (its state, its position, its
/// tracks, its error) is turned into the coordinator's events.
///
/// One engine plays one item, as with every adapter: a channel change is a new engine.
@MainActor
final class AetherPlaybackEngine: PlaybackEngine {
    static var kind: PlaybackEngineKind {
        .aetherEngine
    }

    /// What the video is drawn into (`AetherPlayerSurface`).
    let player: AetherEngine
    /// The subtitle line to draw: the engine publishes cues and leaves the drawing to the app.
    let subtitles = SubtitleDisplay()

    let events: AsyncStream<PlaybackEvent>
    private let output: AsyncStream<PlaybackEvent>.Continuation

    private(set) var state = EngineState.idle
    private(set) var position: Double?
    private(set) var duration: Double?
    private(set) var audioTracks: [TrackDescriptor] = []
    private(set) var subtitleTracks: [TrackDescriptor] = []

    private var subscriptions: Set<AnyCancellable> = []
    private var hasPlayed = false
    private var isLive = false
    private var isStopping = false
    private var lastPositionReport = -1.0

    /// Nil when AetherEngine cannot be created, which the registry reports as "no such engine".
    init?() {
        guard let player = try? AetherEngine() else { return nil }
        self.player = player
        (events, output) = AsyncStream.makeStream()
    }

    // MARK: - Loading

    func load(_ item: PlaybackItem) async throws {
        guard let url = URL(string: item.url), url.scheme != nil else {
            throw PlaybackError(code: .invalidAddress, message: "That is not a valid stream address.")
        }
        isLive = item.mediaKind == .live

        var headers = item.headers
        if let agent = item.userAgent {
            headers["User-Agent"] = agent
        }
        var options = LoadOptions(httpHeaders: headers, isLive: isLive)
        // A live channel can be paused and gone back in for half an hour. The engine keeps the window on disk.
        if isLive {
            options.dvrWindowSeconds = 1800
        }

        observe()
        setState(.opening)
        do {
            try await player.load(
                url: url,
                startPosition: item.startPosition.flatMap { $0 > 0 ? $0 : nil },
                options: options
            )
        } catch {
            setState(.failed)
            throw Self.map(error, info: player.errorInfo)
        }
        refreshTracks()
    }

    /// The engine's state, as Combine publishes it, turned into events as it changes.
    private func observe() {
        player.$state
            .removeDuplicates()
            .sink { [weak self] in self?.handle($0) }
            .store(in: &subscriptions)
        player.$isBuffering
            .removeDuplicates()
            .sink { [weak self] buffering in self?.bufferingChanged(buffering) }
            .store(in: &subscriptions)
        player.clock.$currentTime
            .sink { [weak self] in self?.positionChanged($0) }
            .store(in: &subscriptions)
        player.$duration
            .sink { [weak self] seconds in
                guard let self, !isLive else { return }
                duration = seconds > 0 ? seconds : nil
            }
            .store(in: &subscriptions)
        Publishers.CombineLatest(player.$audioTracks, player.$subtitleTracks)
            .sink { [weak self] _, _ in self?.refreshTracks() }
            .store(in: &subscriptions)
        player.$subtitleCues
            .sink { [weak self] cues in
                // Image cues (DVD and Blu-ray bitmaps) are not drawn; text and styled text are, as plain text.
                let text = cues.compactMap(\.text).joined(separator: "\n")
                self?.subtitles.set(text.isEmpty ? nil : text)
            }
            .store(in: &subscriptions)
    }

    // MARK: - Controls

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
        setState(.paused)
    }

    func seek(to seconds: Double) {
        Task { await player.seek(to: seconds) }
    }

    func selectAudioTrack(id: String?) {
        guard let index = id.flatMap({ Int($0) }) else { return }
        player.selectAudioTrack(index: index)
    }

    func selectSubtitleTrack(id: String?) {
        if let index = id.flatMap({ Int($0) }) {
            player.selectSubtitleTrack(index: index)
        } else {
            player.clearSubtitle()
            subtitles.set(nil)
        }
    }

    func stop() async {
        isStopping = true
        subscriptions.removeAll()
        subtitles.set(nil)
        player.stop()
        state = .idle
        output.finish()
    }

    // MARK: - What the engine reports

    private func handle(_ new: PlaybackState) {
        guard !isStopping else { return }
        switch new {
        case .idle:
            break
        case .loading:
            setState(.opening)
        case .playing:
            if !hasPlayed {
                hasPlayed = true
                output.yield(.ready(duration: duration))
                output.yield(.tracksChanged(audio: audioTracks, subtitle: subtitleTracks))
            }
            setState(.playing)
        case .paused:
            setState(.paused)
        case .seeking:
            setState(.buffering)
        case .ended:
            setState(.ended)
            output.yield(.ended)
        case .error:
            setState(.failed)
            output.yield(.failed(Self.map(AetherEngineFailure(), info: player.errorInfo)))
        }
    }

    private func bufferingChanged(_ buffering: Bool) {
        guard !isStopping, hasPlayed else { return }
        if buffering {
            setState(.buffering)
        } else if state == .buffering {
            setState(.playing)
        }
    }

    private func positionChanged(_ seconds: Double) {
        guard !isStopping else { return }
        position = seconds
        guard state == .playing, seconds.rounded(.down) != lastPositionReport else { return }
        lastPositionReport = seconds.rounded(.down)
        output.yield(.positionChanged(seconds: seconds))
    }

    private func refreshTracks() {
        audioTracks = player.audioTracks.map(Self.descriptor)
        subtitleTracks = player.subtitleTracks.map(Self.descriptor)
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

    nonisolated static func descriptor(_ track: TrackInfo) -> TrackDescriptor {
        let label = track.name.isEmpty ? (track.language ?? "Track \(track.id)") : track.name
        return TrackDescriptor(
            id: String(track.id),
            label: label,
            languageCode: track.language,
            isForced: track.isForced
        )
    }

    /// A stand-in for the failure the state carries only as a sentence: the machine-readable kind is in `errorInfo`.
    struct AetherEngineFailure: Error {}

    nonisolated static func map(_ error: Error, info: PlaybackErrorInfo?) -> PlaybackError {
        if let engineError = error as? AetherEngineError {
            switch engineError {
            case .noVideoStream, .noAudioStream, .dolbyVisionUnplayableOnSoftwarePath:
                return PlaybackError(code: .unsupportedFormat, message: engineError.errorDescription)
            default:
                break
            }
        }
        let message = info?.message ?? "AetherEngine stopped with an error."
        guard let kind = info?.kind else {
            return PlaybackError(code: .openFailed, message: message)
        }
        let code: PlaybackError.Code = switch kind {
        case .sourceCertificateRejected: .secureConnectionFailed
        case .sourceRefused, .sourceRateLimited, .liveSourceUnavailable, .vodSourceFailed: .network
        case .dolbyVisionRequiresHardware, .demuxedAudioLiveUnsupported: .unsupportedFormat
        case .softwarePipelineFailed, .nativeItemFailed, .masterPlaylistRejected: .decodeFailed
        default: .openFailed
        }
        return PlaybackError(code: code, message: message)
    }
}
