#if os(macOS) || os(tvOS)
    import SwiftUI

    /// The main window of a Mac, and the screen of an Apple TV: the app, and under it the stream when one is playing in
    /// the window.
    ///
    /// The player is kept mounted the whole time a stream plays, whether it is in front or behind, so moving between
    /// the app's screens never restarts it. In front, the app is invisible and cannot be clicked; behind, the app is
    /// drawn over it with its backgrounds made see-through (`overStream`), and something says what is playing: a small
    /// bar
    /// at the bottom on a Mac, and on Apple TV a panel down the right side that the Right arrow reaches from any row.
    struct MainWindow<Content: View>: View {
        @Environment(EmbeddedPlayback.self) private var playback
        @ViewBuilder let content: () -> Content
        @Namespace private var focusSpace
        #if os(tvOS)
            @Environment(\.resetFocus) private var resetFocus
        #endif

        private var showsNowPlaying: Bool {
            playback.isPlaying && !playback.isFront
        }

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
                app
            }
            #if os(macOS)
            // The window's toolbar (the tabs, the filter and sort) is for the app: out of the way while the stream
            // is in front, back when it goes behind.
            .toolbar(playback.isFront ? .hidden : .automatic, for: .windowToolbar)
            #endif
            #if os(tvOS)
            .focusScope(focusSpace)
            .onChange(of: playback.isFront) { _, front in
                if front {
                    // To the player's controls, so Menu goes back to the app.
                    resetFocus(in: focusSpace)
                } else {
                    // To the panel that says what is playing (Select shows the stream again, Left is the rest of the
                    // app),
                    // once it is on the screen.
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        playback.focusPanel()
                    }
                }
            }
            #endif
            .animation(.snappy(duration: 0.25), value: playback.isFront)
            .animation(.snappy(duration: 0.25), value: playback.isPlaying)
        }

        @ViewBuilder
        private var app: some View {
            #if os(tvOS)
                content()
                    .environment(\.overStream, showsNowPlaying)
                    // The panel itself is part of each screen (`nowPlayingPanel`).
                    // Play/Pause on the remote brings the stream back, from wherever in the app it was left.
                    .onPlayPauseCommand {
                        if showsNowPlaying {
                            playback.bringToFront()
                        }
                    }
                    .opacity(playback.isFront ? 0 : 1)
                    .allowsHitTesting(!playback.isFront)
                    // Hidden is not out of the way on Apple TV, where the remote moves focus without a pointer: the app
                    // under the stream would still take it.
                    .disabled(playback.isFront)
                    .accessibilityHidden(playback.isFront)
            #else
                content()
                    .environment(\.overStream, showsNowPlaying)
                    .opacity(playback.isFront ? 0 : 1)
                    .allowsHitTesting(!playback.isFront)
                    .accessibilityHidden(playback.isFront)
                    .overlay(alignment: .bottom) {
                        if showsNowPlaying {
                            NowPlayingBar()
                                .padding(.bottom, 14)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
            #endif
        }
    }

    #if os(macOS)
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
#endif
