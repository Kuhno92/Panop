import AetherEngine
import PanopCore
import PanopPlayback
import SwiftUI

extension EnvironmentValues {
    /// True while the stream plays behind the app (see `EmbeddedPlayback`): its controls are out of sight and cannot
    /// take
    /// the focus or a press, which belong to the app in front.
    @Entry var playerIsBehind: Bool = false
}

/// Resolves what to play, then shows the player. Presented full screen from a
/// channel or movie.
struct PlayerScreen: View {
    let target: PlaybackTarget
    /// Set where the player is not a presentation of its own (a Mac's main window): what Close does, and a way back to
    /// the app that leaves the stream playing.
    var onClose: (() -> Void)?
    var onBrowse: (() -> Void)?
    /// Where the guide is part of the app (a Mac's main window): asks the app to open it, in place of a sheet over the
    /// stream.
    var onShowGuideInApp: (() -> Void)?

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @Environment(\.playbackMetrics) private var metricsStore
    @Environment(\.channelVariants) private var variantsStore
    @Environment(\.modelContext) private var catalog
    @AppStorage(ChannelGrouping.key) private var groupsByGuide = ChannelGrouping.isOnByDefault
    @AppStorage("playbackEngine") private var engineRaw = PlaybackEngineKind.avPlayer.rawValue

    @State private var model: PlayerModel?
    @State private var problem: String?
    /// What plays now, once the person has switched channel from the guide; until then, `target`.
    @State private var switchedTo: PlaybackTarget?
    @State private var showingGuide = false

    private var playing: PlaybackTarget {
        switchedTo ?? target
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                PlayerView(
                    model: model,
                    onClose: onClose,
                    onBrowse: onBrowse,
                    onShowGuide: playing.kind == .live ? (onShowGuideInApp ?? { showingGuide = true }) : nil,
                    guide: guideKey,
                    versions: versionRows.map { TrackDescriptor(id: $0.entryID, label: $0.name) },
                    currentVersion: playing.entryID,
                    onPickVersion: pickVersion
                )
            } else if let problem {
                PlayerProblem(text: problem)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task { resolve() }
        // The other versions of this channel, when the list groups them: read once, then the picker has them.
        .task(id: playing.id) {
            if groupsByGuide, playing.kind == .live {
                variantsStore.request(playlist: playing.playlist, epgKey: playing.epgKey, in: catalog.container)
            }
        }
        .modifier(PlayerGuidePresentation(isPresented: $showingGuide) { switchTo($0) })
    }

    /// The channels that share the playing one's guide key, without any the person hid, when the list is grouped by
    /// guide.
    private var versionRows: [CatalogRow] {
        guard groupsByGuide, playing.kind == .live, playing.catchup == nil else { return [] }
        let all = variantsStore.variants(playlist: playing.playlist, epgKey: playing.epgKey) ?? []
        return all.filter { $0.entryID == playing.entryID || !userState.hidden.contains($0.id) }
    }

    /// Plays another version of the channel and remembers it for the next time the channel is chosen from the list.
    private func pickVersion(_ entryID: String) {
        guard entryID != playing.entryID, let row = versionRows.first(where: { $0.entryID == entryID }) else { return }
        ChannelVersions.remember(row, userState: userState)
        switchTo(PlaybackTarget(row: row))
    }

    /// Where the live channel is in the guide, for its timeline. Not for an aired programme from the archive, which has
    /// a scrubber of its own.
    private var guideKey: GuideKey? {
        guard playing.kind == .live, playing.catchup == nil, let key = playing.epgKey, !key.isEmpty else { return nil }
        return GuideKey(playlist: playing.playlist, epgKey: key)
    }

    /// Plays another channel in place of this one, from the guide.
    private func switchTo(_ new: PlaybackTarget) {
        showingGuide = false
        switchedTo = new
        // The old picture goes, and with it its player; the new one is made as a first one is.
        model = nil
        problem = nil
        resolve()
    }

    private func resolve() {
        guard model == nil else { return }
        let target = playing
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

/// The TV guide over a playing stream: a sheet, or on Apple TV the whole screen. Choosing a channel hands it back.
private struct PlayerGuidePresentation: ViewModifier {
    @Binding var isPresented: Bool
    let onPlay: (PlaybackTarget) -> Void

    @Environment(UserStateStore.self) private var userState
    @AppStorage(ChannelGrouping.key) private var groupsByGuide = ChannelGrouping.isOnByDefault

    func body(content: Content) -> some View {
        #if os(tvOS)
            content.fullScreenCover(isPresented: $isPresented) { guide }
        #else
            content.sheet(isPresented: $isPresented) {
                NavigationStack {
                    guide
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isPresented = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 480)
                #endif
            }
        #endif
    }

    /// Every channel, in the provider's order, minus what the person has hidden.
    private var guide: some View {
        GuideGridView(
            spec: ListSpec(
                kind: .live,
                hidden: userState.hidden,
                hiddenGroups: userState.hiddenCategories(of: .live),
                groupsByGuide: groupsByGuide
            ),
            narrow: { $0 },
            onPlayChannel: onPlay
        )
    }
}

struct PlayerView: View {
    let model: PlayerModel
    var onClose: (() -> Void)?
    var onBrowse: (() -> Void)?
    var onShowGuide: (() -> Void)?
    var guide: GuideKey?
    /// The other versions of the channel that plays, which one plays, and what choosing another does.
    var versions: [TrackDescriptor] = []
    var currentVersion: String?
    var onPickVersion: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.playerIsBehind) private var isBehind

    var body: some View {
        ZStack {
            surface
            subtitles
            tapSurface
            // Not drawn at all while behind the app: faded controls would still show through it and be heard by
            // the accessibility tree and the focus engine.
            if !isBehind {
                overlay
            }
        }
        .disabled(isBehind)
        // Brought back to the front: its controls are up, so the way back to the app is on the screen.
        .onChange(of: isBehind) { _, behind in
            if !behind {
                model.showControls()
            }
        }
        .task { model.start() }
        .onDisappear { Task { await model.stop() } }
        #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .playerWindowWillClose)) { _ in
                Task { await model.stop() }
            }
            // Escape goes back to the app where the stream is in the main window.
            .onExitCommand { onBrowse?() }
        #endif
        #if os(tvOS)
        .onPlayPauseCommand { model.togglePause() }
        // Menu goes back to the app and the stream plays on behind it (nil leaves Menu to the system).
        .onExitCommand(perform: onBrowse)
        #endif
    }

    @ViewBuilder
    private var surface: some View {
        // Each engine draws its own way; a new adapter adds its own case here.
        if let engine = model.engine as? AVPlayerEngine {
            AVPlayerSurface(player: engine.player, onLayer: { engine.attach(layer: $0) }).ignoresSafeArea()
        } else if let engine = model.engine as? AetherPlaybackEngine {
            AetherPlayerSurface(engine: engine.player).ignoresSafeArea()
        } else if let engine = model.engine as? KSPlayerEngine {
            VLCSurface(view: engine.surface).ignoresSafeArea()
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
        } else if let engine = model.engine as? AetherPlaybackEngine {
            SubtitleOverlay(display: engine.subtitles, controlsUp: model.showsControls)
        } else if let engine = model.engine as? KSPlayerEngine {
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
                PlayerControls(
                    model: model,
                    onShowGuide: onShowGuide,
                    guide: guide,
                    versions: versions,
                    currentVersion: currentVersion,
                    onPickVersion: onPickVersion
                )
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

    /// The time of day, at the top right with the controls, so a person watching can tell it without leaving the
    /// picture.
    private var clock: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.headline.monospacedDigit())
        }
        .accessibilityIdentifier("playerClock")
    }

    private var header: some View {
        HStack(alignment: .top) {
            #if !os(tvOS)
                if let onBrowse {
                    // In the main window of a Mac there is no Close here, only the way back to the app: the stream is
                    // stopped from the bar over the app, so it is never stopped by a stray click on the picture.
                    Button(action: onBrowse) {
                        Label("Menu", systemImage: "rectangle.grid.2x2.fill")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Menu")
                    .help("Back to Panop. The stream keeps playing behind it.")
                } else {
                    Button {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline)
                if let engineName = model.engineName {
                    Text(engineName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            clock
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
    @AppStorage(SubtitleStyle.key) private var style = SubtitleStyle.standard

    var body: some View {
        VStack {
            Spacer()
            if let text = display.text {
                SubtitleText(text: text, style: style)
                    .padding(.horizontal, 40)
            }
        }
        .padding(.bottom, (controlsUp ? 110 : 36) + (style.raised ? 90 : 0))
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: controlsUp)
    }
}
