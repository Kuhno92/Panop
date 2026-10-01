import PanopCore
import PanopPlayback
import SwiftUI

/// Resolves what to play, then shows the player. Presented full screen from a
/// channel or movie.
struct PlayerScreen: View {
    let target: PlaybackTarget

    @Environment(PlaylistLibrary.self) private var library
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
                preferred: PlaybackEngineKind(rawValue: engineRaw)
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
            overlay
        }
        .task { model.start() }
        .onDisappear { Task { await model.stop() } }
        #if os(tvOS)
            .onPlayPauseCommand { model.togglePause() }
        #endif
    }

    @ViewBuilder
    private var surface: some View {
        // Each engine draws its own way; a new adapter adds its own case here.
        if let engine = model.engine as? AVPlayerEngine {
            AVPlayerSurface(player: engine.player).ignoresSafeArea()
        } else if let engine = model.engine as? VLCEngine {
            VLCSurface(view: engine.surface).ignoresSafeArea()
        } else if let engine = model.engine as? LumePlaybackEngine {
            // The wrapper only hands an engine-owned view to SwiftUI, whichever engine.
            VLCSurface(view: engine.surface).ignoresSafeArea()
        }
    }

    private var overlay: some View {
        VStack {
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
        }
        .animation(.default, value: model.notice)
        .contentShape(Rectangle())
        #if !os(tvOS)
            .onTapGesture { model.togglePause() }
        #endif
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
