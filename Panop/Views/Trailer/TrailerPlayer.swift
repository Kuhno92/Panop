import PanopCore
import SwiftUI

/// A trailer to play, with the title of what it is for. Only what the app plays itself: a page for the browser is
/// opened
/// instead (see `TrailerRequest.init`).
struct TrailerRequest: Identifiable {
    let id = UUID()
    let source: TrailerSource
    let title: String

    /// Nil for a trailer that is the browser's to open: the caller then opens its address.
    init?(source: TrailerSource, title: String) {
        guard source.isPlayedInApp else { return nil }
        self.source = source
        self.title = title
    }
}

extension TrailerSource {
    /// Whether the app plays it itself (YouTube, a video file) or leaves it to the browser (any other page).
    var isPlayedInApp: Bool {
        switch self {
        case .youtube, .media: true
        case .web: false
        }
    }

    /// Where the browser is to be sent when the app cannot play it.
    var webAddress: URL? {
        switch self {
        case let .youtube(id): URL(string: "https://www.youtube.com/watch?v=\(id)")
        case let .media(url), let .web(url): url
        }
    }
}

extension View {
    /// Plays a trailer in the app: a sheet on an iPhone, iPad or Mac, the whole screen on an Apple TV.
    func trailerPlayer(_ request: Binding<TrailerRequest?>) -> some View {
        #if os(tvOS)
            fullScreenCover(item: request) { TrailerScreen(request: $0) }
        #else
            sheet(item: request) { request in
                NavigationStack {
                    TrailerScreen(request: request)
                }
                #if os(macOS)
                .frame(minWidth: 720, idealWidth: 860, minHeight: 480, idealHeight: 560)
                #endif
            }
        #endif
    }
}

/// The trailer on a black ground, played the way the platform allows: YouTube's own player in a web view on an iPhone,
/// iPad
/// and Mac (the only way YouTube permits), a stream read out of YouTube's page on an Apple TV (which has no web view),
/// and a
/// video file by the system player.
struct TrailerScreen: View {
    let request: TrailerRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if failed {
                unavailable
            } else {
                player
            }
        }
        .navigationTitle(request.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                #if !os(tvOS)
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                #endif
            }
    }

    @ViewBuilder
    private var player: some View {
        switch request.source {
        case let .youtube(id):
            #if os(tvOS)
                ExtractedYouTubeTrailer(videoID: id) { failed = true }
            #else
                YouTubeEmbedView(videoID: id) { failed = true }
            #endif
        case let .media(url):
            MediaTrailerView(url: url) { failed = true }
        case .web:
            EmptyView()
        }
    }

    /// When a trailer cannot be played here: the person is told, and, where a browser exists, can open it there.
    private var unavailable: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.slash").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("This trailer can't be played here.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            #if os(tvOS)
                Button("Close") { dismiss() }
            #else
                if let address = request.source.webAddress {
                    Button("Open in the browser") { openURL(address) }
                        .buttonStyle(.borderedProminent)
                }
            #endif
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}
