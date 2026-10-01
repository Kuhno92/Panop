import PanopCore
import PanopPlayback
import SwiftUI

/// Resolves what to play, then shows the player. Presented full screen from a
/// channel or movie.
struct PlayerScreen: View {
    let target: PlaybackTarget

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @Environment(\.playbackMetrics) private var metricsStore
    @AppStorage("playbackEngine") private var engineRaw = PlaybackEngineKind.avPlayer.rawValue

    @State private var model: PlayerModel?
    @State private var problem: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                PlayerView(model: model)
            } else if let problem {
                PlayerProblem(text: problem)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task { resolve() }
    }

    private func resolve() {
        guard model == nil else { return }
        do {
            let source = try library.descriptor(for: target.playlist)?.source
            let request = try PlaybackRequestBuilder.request(
                for: target,
                source: source,
                transport: URLSessionTransport()
            )
            model = PlayerModel(
                title: target.name,
                request: request,
                preferred: PlaybackEngineKind(rawValue: engineRaw),
                controlsTimeout: UITestMode.controlsTimeout ?? .seconds(4),
                nowPlaying: SystemNowPlaying(),
                startPosition: target.resumeAt ?? 0,
                onProgress: target.kind == .live ? nil : { [userState, key = target.id] position, duration in
                    userState.saveProgress(key, position: position, duration: duration)
                },
                memory: userState,
                memoryKey: target.id,
                metrics: metricsStore
            )
        } catch let error as PlaybackTargetError {
            problem = error.message
        } catch {
            problem = "This item could not be prepared for playback."
        }
    }
}

struct PlayerView: View {
    let model: PlayerModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            surface
            subtitles
            tapSurface
            overlay
        }
        .task { model.start() }
        .onDisappear { Task { await model.stop() } }
        #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .playerWindowWillClose)) { _ in
                Task { await model.stop() }
            }
        #endif
        #if os(tvOS)
        .onPlayPauseCommand { model.togglePause() }
        #endif
    }

    @ViewBuilder
    private var surface: some View {
        // Each engine draws its own way; a new adapter adds its own case here.
        if let engine = model.engine as? AVPlayerEngine {
            AVPlayerSurface(player: engine.player, onLayer: { engine.attach(layer: $0) }).ignoresSafeArea()
        } else if let engine = model.engine as? VLCEngine {
            VLCSurface(view: engine.surface).ignoresSafeArea()
        } else if let engine = model.engine as? LumePlaybackEngine {
            // The wrapper only hands an engine-owned view to SwiftUI, whichever engine.
            VLCSurface(view: engine.surface).ignoresSafeArea()
        }
    }

    /// Subtitle text for the engine that leaves drawing to us. Sits above the controls
    /// while they are up, so neither covers the other.
    @ViewBuilder
    private var subtitles: some View {
        if let engine = model.engine as? LumePlaybackEngine {
            SubtitleOverlay(display: engine.subtitles, controlsUp: model.showsControls)
        }
    }

    private var overlay: some View {
        VStack {
            if model.showsControls {
                header
                    .transition(.opacity)
            }

            Spacer()

            if model.isWorking {
                ProgressView().controlSize(.large).tint(.white)
            }
            if let text = model.failureText {
                PlayerProblem(text: text)
            }
            Spacer()

            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding()
                    .transition(.opacity)
            }

            if model.showsControls, model.failureText == nil {
                PlayerControls(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.notice)
        .animation(.easeOut(duration: 0.2), value: model.showsControls)
    }

    /// The whole picture, as a touch target for showing and hiding the controls.
    ///
    /// A layer of its own, behind the controls. The gesture used to sit on the container that
    /// holds them, and once they hid that container held nothing but spacers: a tap on the
    /// picture then never arrived, so hidden controls could not be brought back (found by a UI
    /// test, which tapped and watched nothing happen). Buttons are above this layer, so they
    /// still get their own taps.
    private var tapSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
        #if !os(tvOS)
            .onTapGesture { model.toggleControls() }
        #else
            // The remote only moves focus, and a view that cannot take focus never hears it.
            // So while the controls are hidden this surface can: any movement or a press of
            // Select brings them up. While they are showing it must not, or it would take
            // the focus from them. Deferred out of the focus engine's animation context.
            .focusable(!model.showsControls)
            .onMoveCommand { _ in Task { model.showControls() } }
            .onTapGesture { Task { model.toggleControls() } }
        #endif
    }

    private var header: some View {
        HStack(alignment: .top) {
            #if !os(tvOS)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline)
                if let engineName = model.engineName {
                    Text(engineName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .foregroundStyle(.white)
        .shadow(radius: 4)
    }
}

private struct PlayerProblem: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle)
            Text(text).multilineTextAlignment(.center)
            Button("Close") { dismiss() }
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: 520)
    }
}

private struct SubtitleOverlay: View {
    let display: SubtitleDisplay
    let controlsUp: Bool

    var body: some View {
        VStack {
            Spacer()
            if let text = display.text {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 40)
            }
        }
        .padding(.bottom, controlsUp ? 110 : 36)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: controlsUp)
    }
}
