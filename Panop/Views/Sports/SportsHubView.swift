import PanopSports
import SwiftData
import SwiftUI

/// The sports hub: today's matches of the leagues and teams the person follows, the one to put first, what is on now,
/// and, where a channel of their playlist has a match, the way to watch it.
struct SportsHubView: View {
    @Environment(SportsAccount.self) private var account
    @Environment(SportsSyncStore.self) private var sync
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.sportsFeed) private var feed
    @Environment(\.modelContext) private var catalog
    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @State private var model: SportsHubModel?
    @State private var showsSelection = false

    var body: some View {
        Group {
            if !account.hasKey {
                SportsNoKeyView()
            } else if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Sports")
        .background { PageBackground() }
        .task(id: [profiles.currentID, account.hasKey ? "key" : "none"]) { await start() }
    }

    private func start() async {
        guard account.hasKey, let feed else {
            model = nil
            return
        }
        let source = SportsHubModel.ChannelSource(
            reader: MatchChannelReader(container: catalog.container),
            playlists: { library.playlists.map(\.id) },
            favourites: { userState.favorites }
        )
        let made = SportsHubModel(
            feed: feed,
            account: account,
            sync: sync,
            profile: profiles.currentID,
            channels: source
        )
        model = made
        await feed.prune()
        await made.run()
    }

    @ViewBuilder
    private func content(_ model: SportsHubModel) -> some View {
        if !sync.isSetupDone(profile: profiles.currentID), !model.hasSelection {
            SportsSetupPrompt { showsSelection = true }
                .sheet(isPresented: $showsSelection) {
                    NavigationStack {
                        SportsSelectionView(isSetup: true) { showsSelection = false }
                    }
                    .sportsSheetSize()
                }
        } else {
            SportsHubScroll(model: model)
        }
    }
}

/// The hub itself, for a person who follows something.
private struct SportsHubScroll: View {
    @Bindable var model: SportsHubModel
    @Environment(SportsSyncStore.self) private var sync
    @Environment(PlaylistLibrary.self) private var library
    @Environment(SyncStatusCenter.self) private var status
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var playing: PlaybackTarget?
    @State private var opened: Fixture?
    @State private var showsSelection = false
    @State private var section: Section = .matches

    /// A column that reads well: wider on a television, which is seen from a distance.
    private static var contentWidth: CGFloat {
        #if os(tvOS)
            1500
        #else
            900
        #endif
    }

    private enum Section: Hashable {
        case matches, tables
    }

    var body: some View {
        // Read, so the hub follows a change of leagues or teams from another device.
        // A declaration, because a view builder takes no plain statement; it makes the screen follow the choices.
        // swiftlint:disable:next redundant_discardable_let
        let _ = sync.revision
        ScrollView {
            LazyVStack(alignment: .leading, spacing: RailMetrics.rowSpacing, pinnedViews: []) {
                header
                if let notice = model.notice {
                    SportsNoticeBanner(notice: notice) { Task { await model.reload(force: true) } }
                        .padding(.horizontal)
                }
                if section == .tables {
                    StandingsView(leagues: model.leagues, followedTeams: model.followedTeamIDs)
                } else if !model.hasLoaded {
                    SportsSkeleton()
                } else if model.layout == .empty {
                    SportsEmptyDay(dayOffset: model.dayOffset, hasSelection: model.hasSelection) {
                        showsSelection = true
                    }
                } else {
                    body(for: model.layout)
                }
                footer
            }
            .padding(.vertical)
            .frame(maxWidth: Self.contentWidth)
            .frame(maxWidth: .infinity)
        }
        #if !os(tvOS)
        .refreshable { await model.reload(force: true) }
        #endif
        .navigationDestination(item: $opened) { fixture in
            MatchDetailView(fixture: fixture, model: model)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsSelection = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel(Text("Leagues and teams"))
            }
            #if !os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.reload(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(Text("Refresh"))
                }
            #endif
        }
        .sheet(isPresented: $showsSelection) {
            NavigationStack {
                SportsSelectionView { showsSelection = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showsSelection = false }
                        }
                    }
            }
            .sportsSheetSize()
        }
        .modifier(PlayerPresentation(target: $playing))
        .task(id: model.dayOffset) { await model.reload() }
        // A playlist that arrived, or a guide that was imported, may be the channel of a match.
        .task(id: [library.playlists.map(\.id).joined(separator: ","), status.isAnySyncing ? "sync" : "idle"]) {
            await model.relink()
        }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(spacing: 14) {
            Picker("Show", selection: $section) {
                Text("Matches").tag(Section.matches)
                Text("Tables").tag(Section.tables)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .frame(maxWidth: 420)
            if section == .matches {
                DayTimeline(selection: $model.dayOffset, today: .now)
            }
        }
    }

    @ViewBuilder
    private func body(for layout: HubLayout) -> some View {
        if let hero = layout.hero {
            HeroMatchCard(
                fixture: hero,
                links: model.links[hero.id] ?? [],
                onOpen: { open(hero) },
                onWatch: { watch($0, in: hero) }
            )
            .padding(.horizontal)
        }
        if layout.scoreboard.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeading("Scores")
                ScoreStrip(fixtures: layout.scoreboard, onOpen: open)
            }
        }
        if !layout.mine.isEmpty, !model.followedTeamIDs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading("My teams")
                ForEach(layout.mine) { fixture in row(fixture) }
            }
        }
        ForEach(layout.sections) { section in
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(LocalizedStringKey(section.name), detail: section.zone, live: section.liveCount)
                ForEach(section.fixtures) { fixture in row(fixture) }
            }
        }
    }

    private func row(_ fixture: Fixture) -> some View {
        MatchRow(
            fixture: fixture,
            followed: model.followedTeamIDs,
            links: model.links[fixture.id] ?? [],
            onOpen: { open(fixture) },
            onWatch: { watch($0, in: fixture) }
        )
        .padding(.horizontal)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let updated = MatchText.updated(model.fetchedAt) {
                Text(updated)
            }
            Text("Data by sportapi.ai")
        }
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func open(_ fixture: Fixture) {
        opened = fixture
    }

    private func watch(_ link: MatchLink, in fixture: Fixture) {
        guard let target = model.target(for: link, in: fixture) else { return }
        playing = target
    }
}

struct SectionHeading: View {
    let title: LocalizedStringKey
    var detail: String?
    var live = 0

    init(_ title: LocalizedStringKey, detail: String? = nil, live: Int = 0) {
        self.title = title
        self.detail = detail
        self.live = live
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.title3.bold()).lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if live > 0 {
                HStack(spacing: 4) {
                    LiveDot()
                    Text("\(live)").font(.caption.monospacedDigit().weight(.bold))
                }
                .foregroundStyle(Color.liveGreen)
            }
        }
        .padding(.horizontal)
        .accessibilityAddTraits(.isHeader)
    }
}
