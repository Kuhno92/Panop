import SwiftUI

extension View {
    /// Apple TV: a slim column down the right side while a stream plays behind the app, with a button to show the
    /// stream
    /// and one to stop it. It is part of each screen, not laid over the whole app: the focus engine does not move out
    /// of
    /// a screen's own focus area to something outside it. Elsewhere it is nothing.
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
            // Beside the screen, in a row of its own, so the screen is really narrower: with the panel laid over it (a
            // safe-area inset) the list's rows still reached under the panel, and the focus engine, finding rows where
            // the panel is, went from the panel's buttons to a channel and never from a row to the panel. Laid out
            // beside it, Right reaches the panel when nothing else on the screen is further right.
            let showing = playback.isPlaying && !playback.isFront
            HStack(spacing: 0) {
                content
                    .environment(\.pageBackgroundProvided, showing)
                if showing {
                    NowPlayingPanel()
                }
            }
            // One gradient behind the screen and its panel, the same as the screen has without one (over the stream,
            // see
            // through), and out to the edge of the screen, past the margin the screen keeps: with the panel's column
            // bare
            // the gradient stopped where the screen did.
            .background {
                if showing {
                    PageBackground()
                }
            }
            .ignoresSafeArea(edges: .trailing)
        }
    }

    /// What is playing behind the app, in as little room as it takes: the channel's name over two round buttons, Show
    /// stream and Stop.
    private struct NowPlayingPanel: View {
        @Environment(EmbeddedPlayback.self) private var playback

        private enum Control: Hashable {
            case show, stop
        }

        @FocusState private var focus: Control?

        var body: some View {
            VStack(spacing: 22) {
                Image(systemName: "play.tv.fill").font(.title2).foregroundStyle(.secondary)
                Text(playback.target?.name ?? "")
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button {
                    playback.bringToFront()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 56, height: 56)
                }
                .buttonBorderShape(.circle)
                .focused($focus, equals: .show)
                .accessibilityLabel("Show stream")
                Button(role: .destructive) {
                    playback.stop()
                } label: {
                    Image(systemName: "stop.fill").frame(width: 56, height: 56)
                }
                .buttonBorderShape(.circle)
                .focused($focus, equals: .stop)
                .accessibilityLabel("Stop")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 28)
            .frame(width: 156)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.trailing, 40)
            .frame(maxHeight: .infinity)
            // A section as tall as the screen: the right arrow from the last button of any row, whatever its height on
            // the screen, is handed to the panel's buttons.
            .focusSection()
            .onChange(of: playback.panelFocusRequests) { focus = .show }
        }
    }
#endif
