import PanopPlayback
import SwiftUI

/// The transport bar: play and pause, a scrubber for video on demand or a LIVE badge for
/// a channel, and the audio and subtitle menus. Shared by every engine, because it only
/// talks to `PlayerModel`.
struct PlayerControls: View {
    let model: PlayerModel

    /// The scrubber's own value while a finger is on it, so the coordinator is asked to
    /// seek once, on release, and not on every movement.
    @State private var scrubbing: Double?

    /// Which control has focus, on Apple TV, so the bar can stay up while it is being used.
    private enum Control: Hashable {
        case play, back, forward, audio, subtitles
    }

    @FocusState private var focused: Control?

    private let skip = 10.0

    /// A focused button on Apple TV grows, and at the usual spacing it covered its neighbour:
    /// the LIVE badge sat half under the Pause button (seen in a UI test screenshot).
    private static var spacing: CGFloat {
        #if os(tvOS)
            48
        #else
            20
        #endif
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .frame(width: 36)
            }
            .trackFocus($focused, .play)
            .accessibilityLabel(model.isPaused ? "Play" : "Pause")

            if model.canSeek {
                Button {
                    model.skip(by: -skip)
                } label: {
                    Image(systemName: "gobackward.10").font(.title3)
                }
                .trackFocus($focused, .back)
                .accessibilityLabel("Back 10 seconds")

                timeline

                Button {
                    model.skip(by: skip)
                } label: {
                    Image(systemName: "goforward.10").font(.title3)
                }
                .trackFocus($focused, .forward)
                .accessibilityLabel("Forward 10 seconds")
            } else {
                liveBadge
                Spacer()
            }

            tracks

            #if !os(tvOS)
                if model.supportsAirPlay {
                    AirPlayButton()
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("AirPlay")
                }
            #endif

            if model.supportsPictureInPicture {
                Button {
                    model.togglePictureInPicture()
                } label: {
                    Image(systemName: "pip.enter").font(.title3)
                }
                .accessibilityLabel("Picture in Picture")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .padding()
        // Focus anywhere in the bar holds it up; letting go starts the countdown again.
        .onChange(of: focused) { model.holdControls(focused != nil) }
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.red, in: Capsule())
            .accessibilityLabel("Live")
    }

    @ViewBuilder
    private var timeline: some View {
        let duration = model.duration ?? 0
        let shown = scrubbing ?? model.position
        Text(PlayerTime.text(shown))
            .font(.caption.monospacedDigit())
        #if os(tvOS)
            // tvOS has no slider; the skip buttons move it.
            ProgressView(value: min(shown, duration), total: max(duration, 1))
        #else
            Slider(
                value: Binding(get: { shown }, set: { scrubbing = $0 }),
                in: 0 ... max(duration, 1)
            ) { editing in
                if !editing, let target = scrubbing {
                    model.seek(to: target)
                    scrubbing = nil
                }
            }
        #endif
        Text("-" + PlayerTime.text(max(duration - shown, 0)))
            .font(.caption.monospacedDigit())
    }

    @ViewBuilder
    private var tracks: some View {
        if model.audioTracks.count > 1 {
            Menu {
                Button {
                    model.selectAudio(id: nil)
                } label: {
                    checked("Default", model.selectedAudioID == nil)
                }
                ForEach(model.audioTracks) { track in
                    Button {
                        model.selectAudio(id: track.id)
                    } label: {
                        checked(track.label, model.selectedAudioID == track.id)
                    }
                }
            } label: {
                Image(systemName: "speaker.wave.2").font(.title3)
            }
            .trackFocus($focused, .audio)
            .accessibilityLabel("Audio")
        }
        if !model.subtitleTracks.isEmpty {
            Menu {
                Button {
                    model.selectSubtitle(id: nil)
                } label: {
                    checked("Off", model.selectedSubtitleID == nil)
                }
                ForEach(model.subtitleTracks) { track in
                    Button {
                        model.selectSubtitle(id: track.id)
                    } label: {
                        checked(track.label, model.selectedSubtitleID == track.id)
                    }
                }
            } label: {
                Image(systemName: "captions.bubble").font(.title3)
            }
            .trackFocus($focused, .subtitles)
            .accessibilityLabel("Subtitles")
        }
    }

    @ViewBuilder
    private func checked(_ text: String, _ isOn: Bool) -> some View {
        if isOn {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }
}

private extension View {
    /// Reports focus to the controls on tvOS, where the remote drives it. Elsewhere a
    /// pointer or touch does the work and there is nothing to track.
    @ViewBuilder
    func trackFocus<Value: Hashable>(_ focus: FocusState<Value?>.Binding, _ value: Value) -> some View {
        #if os(tvOS)
            focused(focus, equals: value)
        #else
            self
        #endif
    }
}
