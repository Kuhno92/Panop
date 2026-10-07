import SwiftUI

extension View {
    /// Apple TV: a panel down the right side while a stream plays behind the app, with Show stream and Stop. It is part
    /// of each screen, not laid over the whole app: the focus engine does not move out of a screen's own focus area
    /// to something outside it, so a panel outside could not be reached with the right arrow. Elsewhere it is nothing.
    func nowPlayingPanel() -> some View {
        #if os(tvOS)
            modifier(NowPlayingPanelModifier())
        #else
            self
        #endif
    }
}

#if os(tvOS)
    private struct NowPlayingPanelModifier: ViewModifier {
        @Environment(EmbeddedPlayback.self) private var playback

        func body(content: Content) -> some View {
            // A column of its own, so the screen is narrower and nothing is hidden behind it, and as tall as the screen
            // so Right from any row reaches it.
            content
                // The right arrow anywhere on the screen goes to the panel. Before the panel is added, so a press
                // inside
                // the panel is not taken for one outside it.
                .onMoveCommand { direction in
                    if direction == .right, playback.isPlaying, !playback.isFront {
                        playback.focusPanel()
                    }
                }
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    if playback.isPlaying, !playback.isFront {
                        NowPlayingPanel()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
        }
    }

    /// What is playing behind the app: Show stream and Stop, one above the other.
    private struct NowPlayingPanel: View {
        @Environment(EmbeddedPlayback.self) private var playback
        @FocusState private var focused: Bool

        var body: some View {
            VStack(spacing: 28) {
                Image(systemName: "play.tv.fill").font(.system(size: 56))
                VStack(spacing: 6) {
                    Text("Now playing").font(.callout).foregroundStyle(.secondary)
                    Text(playback.target?.name ?? "")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }
                VStack(spacing: 16) {
                    Button {
                        playback.bringToFront()
                    } label: {
                        Label("Show stream", systemImage: "arrow.up.left.and.arrow.down.right")
                            .frame(maxWidth: .infinity)
                    }
                    .focused($focused)
                    Button(role: .destructive) {
                        playback.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
            .frame(width: 400)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .onChange(of: playback.panelFocusRequests) { focused = true }
        }
    }
#endif
