import Foundation
import MediaPlayer

#if os(iOS) || os(tvOS)
    import AVFAudio
#endif

/// What the system's media controls show: Control Center, the lock screen, the Siri
/// remote's transport, the media keys on a Mac.
nonisolated struct NowPlayingInfo: Equatable {
    var title: String
    var position: Double
    /// Nil for a live channel.
    var duration: Double?
    var isPlaying: Bool

    var isLive: Bool {
        duration == nil
    }
}

/// What the system asks the player to do.
nonisolated enum RemoteCommand: Equatable {
    case play, pause, toggle
    /// Seconds, negative to go back.
    case skip(Double)
    case seek(Double)
}

/// Where `PlayerModel` tells the system what is playing. A protocol so that the model's
/// behaviour can be tested without touching the real, process-wide media controls.
@MainActor
protocol NowPlayingPublishing: AnyObject {
    /// Takes over the system controls and sends their commands to `onCommand`.
    func begin(onCommand: @escaping @MainActor (RemoteCommand) -> Void)
    func update(_ info: NowPlayingInfo)
    /// Gives the controls back.
    func end()
}

/// The real thing, on `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
@MainActor
final class SystemNowPlaying: NowPlayingPublishing {
    private var registrations: [(command: MPRemoteCommand, token: Any)] = []

    func begin(onCommand: @escaping @MainActor (RemoteCommand) -> Void) {
        end()
        #if os(iOS) || os(tvOS)
            // Without a playback category the system will not show or honour the controls
            // for an app that is not in front, and background audio stops.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        registrations = Self.install { command in
            Task { @MainActor in onCommand(command) }
        }
    }

    func update(_ info: NowPlayingInfo) {
        let center = MPRemoteCommandCenter.shared()
        center.changePlaybackPositionCommand.isEnabled = !info.isLive
        center.skipForwardCommand.isEnabled = !info.isLive
        center.skipBackwardCommand.isEnabled = !info.isLive

        var values: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: info.isLive,
            // The system advances the clock itself from the rate, so this is sent on
            // changes, not every second.
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.position,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? 1.0 : 0.0
        ]
        if let duration = info.duration {
            values[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = values
        MPNowPlayingInfoCenter.default().playbackState = info.isPlaying ? .playing : .paused
    }

    func end() {
        for registration in registrations {
            registration.command.removeTarget(registration.token)
        }
        registrations = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// `nonisolated`, because the system calls these handlers from its own queue. Under the
    /// project's default main-actor isolation Swift would assert the main queue on entry
    /// and trap, as it does for libVLC's delegate (docs/engines.md).
    nonisolated static func install(
        deliver: @escaping @Sendable (RemoteCommand) -> Void
    ) -> [(command: MPRemoteCommand, token: Any)] {
        let center = MPRemoteCommandCenter.shared()
        var registered: [(command: MPRemoteCommand, token: Any)] = []

        func add(_ command: MPRemoteCommand, _ translate: @escaping (MPRemoteCommandEvent) -> RemoteCommand?) {
            command.isEnabled = true
            let token = command.addTarget { event in
                guard let translated = translate(event) else { return .commandFailed }
                deliver(translated)
                return .success
            }
            registered.append((command, token))
        }

        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        add(center.playCommand) { _ in .play }
        add(center.pauseCommand) { _ in .pause }
        add(center.togglePlayPauseCommand) { _ in .toggle }
        add(center.skipForwardCommand) { event in
            .skip((event as? MPSkipIntervalCommandEvent)?.interval ?? 10)
        }
        add(center.skipBackwardCommand) { event in
            .skip(-((event as? MPSkipIntervalCommandEvent)?.interval ?? 10))
        }
        add(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek($0.positionTime) }
        }
        return registered
    }
}
