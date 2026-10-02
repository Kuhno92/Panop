import PanopCore
import SwiftData
import SwiftUI

/// The first screen: what to pick up where it was left, and what has been starred.
///
/// Rails of channel cards, each a bounded fetch by entry id (the favourites and the recent
/// plays live in the cloud container, so the catalog is asked for just those). A rail with
/// nothing in it is not drawn, rather than shown empty.
struct HomeView: View {
    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState

    /// Takes the person to the full channel list.
    let onBrowse: () -> Void

    @State private var showingAdd = false
    @State private var playing: PlaybackTarget?

    /// A rail is a glance, not a list: the list is a tab away.
    private let railLimit = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if library.playlists.isEmpty {
                    noPlaylist
                } else if userState.recents.isEmpty, userState.favorites.isEmpty {
                    nothingYet
                } else {
                    if let last = userState.recents.first {
                        ContinueBanner(key: last, onPlay: play)
                    }
                    ChannelRail(
                        title: "Continue watching",
                        keys: Array(continueKeys.prefix(railLimit)),
                        keepsOrder: true,
                        showsProgress: true,
                        onPlay: play
                    )
                    ChannelRail(
                        title: "Recently watched",
                        // The most recent channel is the banner above, and a film left part-way is
                        // in the rail above, so neither is shown twice.
                        keys: Array(userState.recents.dropFirst().filter { userState.progress[$0] == nil }
                            .prefix(railLimit)),
                        keepsOrder: true,
                        onPlay: play
                    )
                    ChannelRail(
                        title: "Favourites",
                        keys: Array(userState.favorites),
                        keepsOrder: false,
                        onPlay: play
                    )
                    browseButton
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Home")
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
        .modifier(PlayerPresentation(target: $playing))
    }

    /// Unfinished films and episodes, without the one the banner already offers.
    private var continueKeys: [String] {
        userState.continueWatching.filter { $0 != userState.recents.first }
    }

    private func play(_ channel: CatalogEntryRecord) {
        let key = UserStateStore.key(playlist: channel.playlist, entry: channel.id)
        userState.markPlayed(key)
        var target = PlaybackTarget(entry: channel)
        // A film left part-way picks up there: Home is the quick way back in, so it does not ask.
        if channel.kind != .live {
            target.resumeAt = userState.resumePosition(for: key)
        }
        playing = target
    }

    private var noPlaylist: some View {
        ContentUnavailableView {
            Label("Welcome to Panop", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("Add an M3U playlist or Xtream provider to get started.")
        } actions: {
            Button("Add playlist") { showingAdd = true }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var nothingYet: some View {
        ContentUnavailableView {
            Label("Nothing here yet", systemImage: "house")
        } description: {
            Text("Channels you watch, and the ones you star, show up here.")
        } actions: {
            Button("Browse Live TV", action: onBrowse)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var browseButton: some View {
        Button("Browse all channels", systemImage: "tv", action: onBrowse)
            .padding(.horizontal)
    }
}

/// One horizontal row of channel cards.
struct ChannelRail: View {
    @Query private var channels: [CatalogEntryRecord]
    @Environment(UserStateStore.self) private var userState

    let title: String
    let keys: [String]
    /// Recents are shown in the order they were watched; favourites by name.
    let keepsOrder: Bool
    /// Draws how far through each title someone got, for the films and episodes left part-way.
    var showsProgress = false
    let onPlay: (CatalogEntryRecord) -> Void

    init(
        title: String,
        keys: [String],
        keepsOrder: Bool,
        showsProgress: Bool = false,
        onPlay: @escaping (CatalogEntryRecord) -> Void
    ) {
        self.title = title
        self.keys = keys
        self.keepsOrder = keepsOrder
        self.showsProgress = showsProgress
        self.onPlay = onPlay
        _channels = Query(LiveChannelQuery.descriptor(
            restrictedTo: Array(Set(keys.map(UserStateStore.entryID(in:)))),
            kind: nil
        ))
    }

    /// The query matched on entry id alone, and an id can repeat across playlists, so the
    /// playlist is checked here.
    private var shown: [CatalogEntryRecord] {
        let wanted = Set(keys)
        let matching = channels.filter { wanted.contains(key(of: $0)) }
        guard keepsOrder else { return matching }
        let byKey = Dictionary(matching.map { (key(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        return keys.compactMap { byKey[$0] }
    }

    private func key(of channel: CatalogEntryRecord) -> String {
        UserStateStore.key(playlist: channel.playlist, entry: channel.id)
    }

    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Self.spacing) {
                        ForEach(shown) { channel in
                            ChannelCard(
                                channel: channel,
                                isFavorite: userState.isFavorite(key(of: channel)),
                                progress: showsProgress ? userState.progress[key(of: channel)]?.fraction : nil
                            ) {
                                onPlay(channel)
                            }
                        }
                    }
                    .padding(.horizontal)
                    // A focused card on Apple TV grows, and the row would clip it.
                    .padding(.vertical, Self.verticalRoom)
                }
            }
        }
    }

    private static var spacing: CGFloat {
        #if os(tvOS)
            40
        #else
            14
        #endif
    }

    private static var verticalRoom: CGFloat {
        #if os(tvOS)
            24
        #else
            0
        #endif
    }
}

/// A channel as a card: its logo and its name.
struct ChannelCard: View {
    let channel: CatalogEntryRecord
    let isFavorite: Bool
    /// 0 to 1 for a title left part-way; nil draws no bar.
    var progress: Double?
    let action: () -> Void

    @Environment(UserStateStore.self) private var userState

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ChannelLogo(address: channel.iconURL, size: Self.logoSize)
                Text(channel.name)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: Self.width)
            .overlay(alignment: .bottom) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .accessibilityLabel("Watched")
                        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .padding(8)
                        .accessibilityLabel("Favourite")
                }
            }
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        #endif
        .contextMenu {
            let key = UserStateStore.key(playlist: channel.playlist, entry: channel.id)
            Button {
                userState.toggleFavorite(key)
            } label: {
                Label(
                    isFavorite ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
        }
    }

    private static var width: CGFloat {
        #if os(tvOS)
            260
        #else
            128
        #endif
    }

    private static var logoSize: CGFloat {
        #if os(tvOS)
            120
        #else
            64
        #endif
    }
}

/// The channel watched last, as a large way back into it.
struct ContinueBanner: View {
    @Query private var channels: [CatalogEntryRecord]

    let key: String
    let onPlay: (CatalogEntryRecord) -> Void

    init(key: String, onPlay: @escaping (CatalogEntryRecord) -> Void) {
        self.key = key
        self.onPlay = onPlay
        _channels = Query(LiveChannelQuery.descriptor(restrictedTo: [UserStateStore.entryID(in: key)], kind: nil))
    }

    /// The query matched on entry id alone, so the playlist is checked here.
    private var channel: CatalogEntryRecord? {
        channels.first { UserStateStore.key(playlist: $0.playlist, entry: $0.id) == key }
    }

    var body: some View {
        if let channel {
            Button { onPlay(channel) } label: {
                HStack(spacing: 16) {
                    ChannelLogo(address: channel.iconURL, size: Self.logoSize)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continue watching")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(channel.name)
                            .font(.title2.bold())
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "play.fill")
                        .font(.title2)
                }
                .padding(16)
                // The artwork, enlarged and softened, as the hero's background.
                .background {
                    BackdropView(address: channel.iconURL, blurred: true)
                        .opacity(0.35)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .contentShape(Rectangle())
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            #endif
            .padding(.horizontal)
            .accessibilityLabel("Continue watching \(channel.name)")
        }
    }

    private static var logoSize: CGFloat {
        #if os(tvOS)
            110
        #else
            72
        #endif
    }
}
