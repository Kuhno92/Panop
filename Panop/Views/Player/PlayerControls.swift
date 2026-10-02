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
                    AirPlayButton { model.holdControls($0, reason: "airplay") }
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

    /// One choice among a stream's tracks, as the controls show it.
    private struct Choice {
        var symbol: String
        var label: String
        /// What holds the bar up while the choice is open.
        var reason: String
        var focus: Control
        var noneTitle: String
        var tracks: [TrackDescriptor]
        var selected: String?
        var select: (String?) -> Void
    }

    @ViewBuilder
    private var tracks: some View {
        if model.audioTracks.count > 1 {
            trackChoice(Choice(
                symbol: "speaker.wave.2",
                label: "Audio",
                reason: "audio",
                focus: .audio,
                noneTitle: "Default",
                tracks: model.audioTracks,
                selected: model.selectedAudioID,
                select: model.selectAudio(id:)
            ))
        }
        if !model.subtitleTracks.isEmpty {
            trackChoice(Choice(
                symbol: "captions.bubble",
                label: "Subtitles",
                reason: "subtitles",
                focus: .subtitles,
                noneTitle: "Off",
                tracks: model.subtitleTracks,
                selected: model.selectedSubtitleID,
                select: model.selectSubtitle(id:)
            ))
        }
    }

    /// A choice among a stream's tracks. Apple TV uses a menu, which the remote's focus already
    /// holds the bar up for. Elsewhere it is a popover whose open state is known, so the bar can
    /// be held up while it is open: a plain `Menu` never says when it is showing, and the bar
    /// would go after a few seconds, taking the menu with it.
    @ViewBuilder
    private func trackChoice(_ choice: Choice) -> some View {
        #if os(tvOS)
            Menu {
                Button { choice.select(nil) } label: { checked(choice.noneTitle, choice.selected == nil) }
                ForEach(choice.tracks) { track in
                    Button { choice.select(track.id) } label: { checked(track.label, choice.selected == track.id) }
                }
            } label: {
                Image(systemName: choice.symbol).font(.title3)
            }
            .trackFocus($focused, choice.focus)
            .accessibilityLabel(choice.label)
        #else
            TrackPopoverButton(
                symbol: choice.symbol,
                label: choice.label,
                noneTitle: choice.noneTitle,
                tracks: choice.tracks,
                selected: choice.selected,
                select: choice.select,
                onPresenting: { model.holdControls($0, reason: choice.reason) }
            )
        #endif
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

#if !os(tvOS)
    /// The button for a track choice, and the popover it opens. Reports when the popover is open.
    private struct TrackPopoverButton: View {
        let symbol: String
        let label: String
        let noneTitle: String
        let tracks: [TrackDescriptor]
        let selected: String?
        let select: (String?) -> Void
        let onPresenting: (Bool) -> Void

        @State private var showing = false

        var body: some View {
            Button { showing = true } label: {
                Image(systemName: symbol).font(.title3)
            }
            .accessibilityLabel(label)
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 4) {
                    option(noneTitle, isSelected: selected == nil, id: nil)
                    ForEach(tracks) { track in
                        option(track.label, isSelected: selected == track.id, id: track.id)
                    }
                }
                .padding(12)
                .frame(minWidth: 180, alignment: .leading)
                .foregroundStyle(.primary)
                // On an iPhone a popover would otherwise become a full sheet.
                .presentationCompactAdaptation(.popover)
            }
            // Closing it however it closes, including a tap outside, lets the bar go.
            .onChange(of: showing) { onPresenting(showing) }
        }

        private func option(_ title: String, isSelected: Bool, id: String?) -> some View {
            Button {
                select(id)
                showing = false
            } label: {
                HStack {
                    Text(title)
                    Spacer(minLength: 16)
                    if isSelected {
                        Image(systemName: "checkmark")
                    }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
#endif
