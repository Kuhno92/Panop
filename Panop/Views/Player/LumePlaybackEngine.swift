import Foundation
import LumeEngine
import Observation
import PanopCore
import PanopPlayback

/// The subtitle line to draw, for the one engine that does not draw its own. AVPlayer and
/// libVLC put subtitles in the picture; LumeEngine hands back the text and leaves the
/// drawing to the app.
@MainActor
@Observable
final class SubtitleDisplay {
    fileprivate(set) var text: String?

    /// Set by an engine that publishes cues and leaves the drawing to the app.
    func set(_ new: String?) {
        if new != text {
            text = new
        }
    }
}

/// The LumeEngine adapter, built on its `PlayerSession` rather than the `LumePlayer`
/// facade: the session has the typed event stream and takes a start position at
/// open time, which is what the coordinator needs.
///
/// **It reports; it does not decide.** No retry, no backoff, no fallback (docs/adr/0002).
/// LumeEngine itself would reconnect an HTTP source quietly, which hides the failure
/// from the coordinator, so that is switched off here.
///
/// One session plays one URL, so a channel change is a new engine, as the coordinator
/// already does for every adapter.
@MainActor
final class LumePlaybackEngine: PlaybackEngine {
    static var kind: PlaybackEngineKind {
        .lumeEngine
    }

    let surface = LumeSurfaceView()
    let subtitles = SubtitleDisplay()

    let events: AsyncStream<PlaybackEvent>
    private let output: AsyncStream<PlaybackEvent>.Continuation

    private(set) var state = PlaybackState.idle
    private(set) var position: Double?
    private(set) var duration: Double?
    private(set) var audioTracks: [TrackDescriptor] = []
    private(set) var subtitleTracks: [TrackDescriptor] = []

    private enum Command {
        case play, pause
        case seek(Double)
        case audio(Int32?)
        case subtitle(Int32?)
    }

    private let commands: AsyncStream<Command>
    private let commandSink: AsyncStream<Command>.Continuation

    private var session: PlayerSession?
    /// The one-variant playlist made for this stream, deleted when playback ends.
    private(set) var playlistFile: URL?
    private var tasks: [Task<Void, Never>] = []
    private var hasPlayed = false
    private var isStopping = false
    private var lastError: EngineError?
    private var failurePending = false
    private var stallThreshold = PlayerConfiguration().stallThreshold
    private var lastPositionReport = -1.0
    private var subtitlePoll: Task<Void, Never>?

    init() {
        (events, output) = AsyncStream.makeStream()
        (commands, commandSink) = AsyncStream.makeStream()
    }

    // MARK: - Loading

    func load(_ item: PlaybackItem) async throws {
        guard let url = URL(string: item.url), url.scheme != nil else {
            throw PlaybackError(code: .invalidAddress, message: "That is not a valid stream address.")
        }

        var configuration = PlayerConfiguration()
        configuration.demuxer.enableReconnect = false
        configuration.demuxer.userAgent = item.userAgent
        for (name, value) in item.headers {
            switch name.lowercased() {
            case "user-agent": configuration.demuxer.userAgent = configuration.demuxer.userAgent ?? value
            case "referer": configuration.demuxer.referer = value
            default: configuration.demuxer.httpHeaders[name] = value
            }
        }
        // Applied while the pipeline is built, before the demuxer streams a byte:
        // seeking a running IPTV connection is what some providers cannot survive.
        if let start = item.startPosition, start > 0 {
            configuration.startPosition = start
        }
        stallThreshold = configuration.stallThreshold

        // A multivariant HLS playlist makes the engine open every variant before it starts.
        let choice = await HLSVariantPicker.choose(for: item)
        playlistFile = choice.file
        if choice.file != nil {
            configuration.demuxer.formatOptions.merge(HLSVariantPicker.formatOptions) { _, new in new }
        }

        let session = PlayerSession(configuration: configuration)
        self.session = session
        surface.install(layer: session.renderer.displayLayer)
        observe(session)
        setState(.opening)

        do {
            let info = try await session.open(url: choice.address)
            duration = info.duration.map(MediaTime.seconds)
            audioTracks = info.audioTracks.map(Self.descriptor)
            subtitleTracks = info.subtitleTracks.map(Self.descriptor)
        } catch {
            setState(.failed)
            throw Self.map(error)
        }
    }

    private func observe(_ session: PlayerSession) {
        tasks.append(Task { [weak self] in
            for await event in session.events {
                self?.handle(event)
            }
        })
        // Commands run in the order they were given. Separate tasks per command
        // would not promise that, and play-then-pause must not become pause-then-play.
        tasks.append(Task { [commands] in
            for await command in commands {
                switch command {
                case .play: await session.play()
                case .pause: await session.pause()
                case let .seek(seconds): await session.seek(to: seconds)
                case let .audio(index): if let index {
                        await session.selectAudioTrack(index)
                    }
                case let .subtitle(index): await session.selectSubtitleTrack(index)
                }
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.tick(session)
            }
        })
    }

    // MARK: - Controls

    func play() {
        commandSink.yield(.play)
    }

    func pause() {
        commandSink.yield(.pause)
        setState(.paused)
    }

    func seek(to seconds: Double) {
        commandSink.yield(.seek(seconds))
    }

    func selectAudioTrack(id: String?) {
        commandSink.yield(.audio(id.flatMap { Int32($0) }))
    }

    func selectSubtitleTrack(id: String?) {
        commandSink.yield(.subtitle(id.flatMap { Int32($0) }))
        if id == nil {
            stopSubtitlePoll()
        } else {
            startSubtitlePoll()
        }
    }

    /// Loads a sidecar file (SRT, VTT, ASS) and shows it. Replaces any embedded selection.
    func loadExternalSubtitles(url: String) async throws {
        guard let session else {
            throw PlaybackError(code: .internalError, message: "Nothing is loaded to add subtitles to.")
        }
        do {
            try await session.loadExternalSubtitles(url: url)
        } catch {
            throw Self.map(error)
        }
        startSubtitlePoll()
    }

    /// Cues are looked up against the playback clock about ten times a second, and only
    /// while subtitles are on, so a stream without them pays nothing for this.
    private func startSubtitlePoll() {
        guard subtitlePoll == nil, let session else { return }
        subtitlePoll = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateSubtitle(session)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopSubtitlePoll() {
        subtitlePoll?.cancel()
        subtitlePoll = nil
        subtitles.text = nil
    }

    private func updateSubtitle(_ session: PlayerSession) {
        let now = session.renderer.currentTime
        let text: String? = if MediaTime.isValid(now) {
            session.subtitles.activeCues(at: now).map(\.text).joined(separator: "\n").nilIfEmpty
        } else {
            nil
        }
        if text != subtitles.text {
            subtitles.text = text
        }
    }

    func stop() async {
        isStopping = true
        commandSink.finish()
        stopSubtitlePoll()
        tasks.forEach { $0.cancel() }
        tasks = []
        surface.removeLayer()
        if let session {
            await session.shutdown()
        }
        session = nil
        if let playlistFile {
            try? FileManager.default.removeItem(at: playlistFile)
            self.playlistFile = nil
        }
        state = .idle
        output.finish()
    }

    // MARK: - Events from the session

    private func handle(_ event: PlayerEvent) {
        guard !isStopping else { return }
        switch event {
        case let .stateChanged(new):
            stateChanged(new)
        case let .error(error):
            // Not every error ends the session. The fatal one is announced as
            // `.failed` first and explained by this event just after.
            lastError = error
            if failurePending {
                reportFailure()
            }
        case .stalled:
            // The session reports the stall after its threshold, so that is how long it was.
            output.yield(.stalled(seconds: stallThreshold))
        case .opened, .decoderDowngraded, .didSeek:
            break
        @unknown default:
            break
        }
    }

    private func stateChanged(_ new: PlayerSession.State) {
        switch new {
        case .idle, .ready:
            break
        case .opening:
            setState(.opening)
        case .buffering:
            setState(.buffering)
        case .playing:
            if !hasPlayed {
                hasPlayed = true
                output.yield(.ready(duration: duration))
                output.yield(.tracksChanged(audio: audioTracks, subtitle: subtitleTracks))
            }
            setState(.playing)
        case .paused:
            setState(.paused)
        case .ended:
            setState(.ended)
            output.yield(.ended)
        case .failed:
            guard state != .failed else { return }
            setState(.failed)
            // The session sets `.failed` before it emits the error that explains it, so
            // reporting now would carry no reason. Wait for the error, but not forever.
            failurePending = true
            tasks.append(Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.reportFailure()
            })
        @unknown default:
            break
        }
    }

    private func reportFailure() {
        guard failurePending, !isStopping else { return }
        failurePending = false
        let error = lastError.map(Self.map)
            ?? PlaybackError(code: hasPlayed ? .network : .openFailed, message: "LumeEngine stopped with an error.")
        output.yield(.failed(error))
    }

    private func tick(_ session: PlayerSession) async {
        guard !isStopping, state == .playing || state == .buffering else { return }
        let seconds = await session.position
        position = seconds
        guard state == .playing, seconds.rounded(.down) != lastPositionReport else { return }
        lastPositionReport = seconds.rounded(.down)
        output.yield(.positionChanged(seconds: seconds))
    }

    private func setState(_ new: PlaybackState) {
        guard new != state else { return }
        state = new
        output.yield(.stateChanged(new))
    }

    // MARK: - Translation

    nonisolated static func descriptor(_ track: TrackInfo) -> TrackDescriptor {
        let label = track.title ?? track.language ?? "Track \(track.index + 1)"
        return TrackDescriptor(
            id: String(track.index),
            label: label,
            languageCode: track.language,
            isForced: track.isForced
        )
    }

    /// FFmpeg's `AVERROR_INVALIDDATA`: it read the bytes and they are not a container
    /// it knows. Another engine may do better, so it is a format failure, not an open one.
    nonisolated static let invalidData: Int32 = -1_094_995_529

    nonisolated static func map(_ error: Error) -> PlaybackError {
        guard let error = error as? EngineError else {
            return PlaybackError(code: .internalError, message: "\(error)")
        }
        let code: PlaybackError.Code = switch error.code {
        case .openFailed: error.ffmpegCode == invalidData ? .unsupportedFormat : .openFailed
        case .ioError: .network
        case .decoderInitFailed, .unsupported, .renderFailed: .unsupportedFormat
        case .decodeFailed: .decodeFailed
        case .cancelled: .cancelled
        case .seekFailed, .invalidState, .internalError: .internalError
        @unknown default: .internalError
        }
        return PlaybackError(code: code, message: error.message)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
