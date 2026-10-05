#if os(macOS)
    import SwiftUI

    /// The main window of a Mac: the app, and under it the stream when one is playing in the window.
    ///
    /// The player is kept mounted the whole time a stream plays, whether it is in front or behind, so moving between
    /// the app's screens never restarts it. In front, the app is invisible and cannot be clicked; behind, the app is
    /// drawn over it with its backgrounds made see-through (`overStream`), and a small bar says what is playing.
    struct MainWindow<Content: View>: View {
        @Environment(EmbeddedPlayback.self) private var playback
        @ViewBuilder let content: () -> Content

        var body: some View {
            ZStack {
                if let target = playback.target {
                    PlayerScreen(
                        target: target,
                        onClose: { playback.stop() },
                        onBrowse: { playback.sendToBack() }
                    )
                    .id(target.id)
                }
                content()
                    .environment(\.overStream, playback.isPlaying && !playback.isFront)
                    .opacity(playback.isFront ? 0 : 1)
                    .allowsHitTesting(!playback.isFront)
                    .overlay(alignment: .bottom) {
                        if playback.isPlaying, !playback.isFront {
                            NowPlayingBar()
                                .padding(.bottom, 14)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
            }
            // The window's toolbar (the tabs, the filter and sort) is for the app: out of the way while the stream is
            // in front, back when it goes behind.
            .toolbar(playback.isFront ? .hidden : .automatic, for: .windowToolbar)
            .animation(.snappy(duration: 0.25), value: playback.isFront)
            .animation(.snappy(duration: 0.25), value: playback.isPlaying)
        }
    }

    /// What is playing behind the app, with the two things to do about it.
    private struct NowPlayingBar: View {
        @Environment(EmbeddedPlayback.self) private var playback

        var body: some View {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill").font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Now playing").font(.caption).foregroundStyle(.secondary)
                    Text(playback.target?.name ?? "").font(.headline).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button("Show stream", systemImage: "arrow.up.left.and.arrow.down.right") {
                    playback.bringToFront()
                }
                Button("Stop", systemImage: "stop.fill", role: .destructive) {
                    playback.stop()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.horizontal, 20)
        }
    }
#endif
