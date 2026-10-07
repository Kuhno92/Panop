#if os(macOS) || os(tvOS)
    import SwiftUI

    /// The main window of a Mac, and the screen of an Apple TV: the app, and under it the stream when one is playing in
    /// the window.
    ///
    /// The player is kept mounted the whole time a stream plays, whether it is in front or behind, so moving between
    /// the app's screens never restarts it. In front, the app is invisible and cannot be clicked; behind, the app is
    /// drawn over it with its backgrounds made see-through (`overStream`), and a small bar says what is playing.
    struct MainWindow<Content: View>: View {
        @Environment(EmbeddedPlayback.self) private var playback
        @ViewBuilder let content: () -> Content
        @Namespace private var focusSpace
        #if os(tvOS)
            @Environment(\.resetFocus) private var resetFocus
        #endif

        var body: some View {
            ZStack {
                if let target = playback.target {
                    PlayerScreen(
                        target: target,
                        onClose: { playback.stop() },
                        onBrowse: { playback.sendToBack() },
                        onShowGuideInApp: { playback.showGuide() }
                    )
                    .id(target.id)
                    .environment(\.playerIsBehind, !playback.isFront)
                }
                content()
                    .environment(\.overStream, playback.isPlaying && !playback.isFront)
                #if os(tvOS)
                    // Play/Pause on the remote brings the stream back, from wherever in the app it was left.
                    .onPlayPauseCommand {
                        if playback.isPlaying, !playback.isFront {
                            playback.bringToFront()
                        }
                    }
                #endif
                    .opacity(playback.isFront ? 0 : 1)
                    .allowsHitTesting(!playback.isFront)
                    // Hidden is not out of the way on Apple TV, where the remote moves focus without a pointer: the app
                    // under the stream would still take it.
                    .disabled(playback.isFront)
                    .accessibilityHidden(playback.isFront)
                    .overlay(alignment: .bottom) {
                        if playback.isPlaying, !playback.isFront {
                            NowPlayingBar(focusSpace: focusSpace)
                            #if os(tvOS)
                                .focusScope(focusSpace)
                            #endif
                                .padding(.bottom, 14)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
            }
            #if os(macOS)
            // The window's toolbar (the tabs, the filter and sort) is for the app: out of the way while the stream
            // is in front, back when it goes behind.
            .toolbar(playback.isFront ? .hidden : .automatic, for: .windowToolbar)
            #endif
            #if os(tvOS)
            // Back at the app from the stream, the focus is on the bar: Select shows the stream again, and the rest of
            // the app is one press up.
            .focusScope(focusSpace)
            .onChange(of: playback.isFront) {
                // To the bar when the stream goes behind, to the player's controls when it comes forward.
                resetFocus(in: focusSpace)
            }
            #endif
            .animation(.snappy(duration: 0.25), value: playback.isFront)
            .animation(.snappy(duration: 0.25), value: playback.isPlaying)
        }
    }

    /// What is playing behind the app, with the two things to do about it.
    private struct NowPlayingBar: View {
        @Environment(EmbeddedPlayback.self) private var playback
        /// The scope the app's focus is reset into when the stream goes behind (Apple TV): the bar's first button is
        /// where it lands.
        let focusSpace: Namespace.ID

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
                #if os(tvOS)
                .prefersDefaultFocus(in: focusSpace)
                #endif
                Button("Stop", systemImage: "stop.fill", role: .destructive) {
                    playback.stop()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            #if os(tvOS)
                .frame(maxWidth: 1100)
            #else
                .frame(maxWidth: 560)
            #endif
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .padding(.horizontal, 20)
        }
    }
#endif
