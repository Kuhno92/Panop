import SwiftData
import SwiftUI

/// The programme guide for the channels of the current list: a grid with a channel down the left, time
/// along the top, and each programme as wide as it is long. The channel column and the time bar stay in
/// view as it scrolls, and a red line marks now.
///
/// It reads the same list the Live TV screen shows (the source, category, search and favourites chosen
/// there) and takes the channels as they scroll into view, a few hundred at most, each with one background
/// read of its programmes. Nothing here reads the guide on the main thread.
struct GuideGridView: View {
    let spec: ListSpec
    /// Narrows the rows read for `spec` the way the Live TV list does (favourites, recents, source, search).
    let narrow: ([CatalogRow]) -> [CatalogRow]

    @Environment(UserStateStore.self) private var userState
    @Environment(\.modelContext) private var catalog
    @State private var list = CatalogListModel()
    @State private var grid = GuideGridModel()
    @State private var timeline = GuideTimeline.around(.now, pointsPerHour: GuideMetrics.pointsPerHour)
    @State private var selected: GuideSelection?
    @State private var playing: PlaybackTarget?
    @State private var position = ScrollPosition()
    /// Apple TV moves by focus, so it is told where to start: on the first channel, not wherever it lands.
    @FocusState private var focusedChannel: String?

    var body: some View {
        let rows = narrow(list.rows)
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { channel in
                        GuideGridRow(
                            channel: channel,
                            timeline: timeline,
                            grid: grid,
                            focus: $focusedChannel,
                            onPlay: play,
                            onSelect: { selected = GuideSelection(channel: channel, programme: $0) }
                        )
                        .onAppear { list.rowAppeared(channel) }
                    }
                } header: {
                    GuideTimeHeader(timeline: timeline)
                }
            }
            .frame(width: GuideMetrics.channelWidth + timeline.width, alignment: .leading)
            // Behind the rows, so the line shows through the gaps and the light cells but never over a title.
            .background(alignment: .topLeading) { GuideNowMarker(timeline: timeline) }
        }
        .scrollPosition($position)
        .coordinateSpace(.named(GuideMetrics.space))
        #if os(tvOS)
            // A full-screen cover shows what is under it unless it is told not to, and the channel column
            // must reach the edge of the screen or the programmes show in the gap beside it.
            .background(Color.black.ignoresSafeArea())
            .ignoresSafeArea(edges: .horizontal)
        #endif
            .overlay {
                if rows.isEmpty, list.phase == .loaded {
                    ContentUnavailableView("No channels", systemImage: "tv")
                }
            }
        #if !os(tvOS)
            .navigationTitle("TV Guide")
        #endif
            .onChange(of: rows.first?.id, initial: true) {
                if focusedChannel == nil {
                    focusedChannel = rows.first?.id
                }
            }
            .task(id: spec) { list.show(spec, in: catalog.container) }
            .task(id: timeline) {
                grid.reset(window: timeline.start ... timeline.end)
                // Open on now, a little in from the channel column, not on the hour the axis begins at.
                position.scrollTo(x: max(0, timeline.x(for: .now) - 40))
            }
            .sheet(item: $selected) { selection in
                GuideProgrammeSheet(
                    selection: selection,
                    onPlay: { selected = nil; play($0) },
                    onPlayTarget: { selected = nil; playing = $0 }
                )
            }
            .modifier(PlayerPresentation(target: $playing))
    }

    private func play(_ channel: CatalogRow) {
        userState.markPlayed(channel.id)
        playing = PlaybackTarget(row: channel)
    }
}

/// Sizes the grid is drawn at. Apple TV is read from a distance, so everything is larger.
enum GuideMetrics {
    static let space = "guideScroll"

    #if os(tvOS)
        static let pointsPerHour = 560.0
        static let channelWidth = 280.0
        static let rowHeight = 110.0
        static let headerHeight = 64.0
    #else
        static let pointsPerHour = 330.0
        static let channelWidth = 132.0
        static let rowHeight = 66.0
        static let headerHeight = 34.0
    #endif
}

/// A programme picked on the grid, with the channel it is on.
struct GuideSelection: Identifiable {
    var channel: CatalogRow
    var programme: ProgrammeSnapshot

    var id: String {
        "\(channel.id)|\(programme.start.timeIntervalSince1970)"
    }
}

/// Keeps a view at the left edge of the grid however far it has scrolled sideways, so the channel column
/// stays in view. Done on the render side, so scrolling does not re-run any view's body.
private extension View {
    func stuckToLeadingEdge() -> some View {
        visualEffect { content, proxy in
            content.offset(x: max(0, -proxy.frame(in: .named(GuideMetrics.space)).minX))
        }
    }
}

private extension View {
    /// Keeps a view clear of the channel column: when its left edge has scrolled in under the column it
    /// moves right to the column's edge, but never past `limit` points, so it stays inside what it belongs to.
    func stayingClearOfChannelColumn(limit: Double) -> some View {
        visualEffect { content, proxy in
            let left = proxy.frame(in: .named(GuideMetrics.space)).minX
            return content.offset(x: max(0, min(GuideMetrics.channelWidth - left, limit)))
        }
    }
}

// MARK: - Time bar

/// Solid behind the channel column, so programmes scrolled under it do not show through.
private struct GuideColumnBackground: View {
    var body: some View {
        #if os(tvOS)
            Rectangle().fill(Color(white: 0.12))
        #else
            Rectangle().fill(.background)
        #endif
    }
}

/// The bar's background: the system's bar material, which Apple TV does not have, so a plain tint there.
private struct GuideBarBackground: View {
    var body: some View {
        #if os(tvOS)
            Rectangle().fill(Color(white: 0.16))
        #else
            Rectangle().fill(.bar)
        #endif
    }
}

private struct GuideTimeHeader: View {
    let timeline: GuideTimeline

    var body: some View {
        HStack(spacing: 0) {
            GuideBarBackground()
                .frame(width: GuideMetrics.channelWidth, height: GuideMetrics.headerHeight)
                .overlay {
                    #if os(tvOS)
                        Text("TV Guide").font(.headline)
                    #else
                        Image(systemName: "clock").foregroundStyle(.secondary).accessibilityHidden(true)
                    #endif
                }
                .stuckToLeadingEdge()
                .zIndex(1)
            ZStack(alignment: .topLeading) {
                GuideBarBackground()
                ForEach(timeline.ticks, id: \.self) { tick in
                    let whole = GuideTimeline.isWholeHour(tick)
                    Rectangle()
                        .fill(.secondary.opacity(whole ? 0.5 : 0.25))
                        .frame(width: 1, height: whole ? GuideMetrics.headerHeight : GuideMetrics.headerHeight / 2)
                        .offset(x: timeline.x(for: tick))
                    Text(tick.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(whole ? .primary : .secondary)
                        .padding(.leading, 6)
                        .offset(x: timeline.x(for: tick))
                }
            }
            .frame(width: timeline.width, height: GuideMetrics.headerHeight)
        }
        .frame(height: GuideMetrics.headerHeight)
    }
}

/// The red line at the current time, running the height of the grid.
private struct GuideNowMarker: View {
    let timeline: GuideTimeline

    var body: some View {
        TimelineView(.everyMinute) { context in
            Rectangle()
                .fill(.red)
                .frame(width: 2)
                .offset(x: GuideMetrics.channelWidth + timeline.x(for: context.date) - 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

private struct GuideGridRow: View {
    let channel: CatalogRow
    let timeline: GuideTimeline
    let grid: GuideGridModel
    var focus: FocusState<String?>.Binding
    let onPlay: (CatalogRow) -> Void
    let onSelect: (ProgrammeSnapshot) -> Void

    @Environment(\.modelContext) private var catalog

    private var key: GuideKey? {
        guard let epgKey = channel.epgKey, !epgKey.isEmpty else { return nil }
        return GuideKey(playlist: channel.playlist, epgKey: epgKey)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { onPlay(channel) } label: {
                HStack(spacing: 8) {
                    ChannelLogo(address: channel.iconURL, size: GuideMetrics.rowHeight * 0.5)
                    Text(channel.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 8)
                .frame(width: GuideMetrics.channelWidth, height: GuideMetrics.rowHeight, alignment: .leading)
                .background { GuideColumnBackground() }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused(focus, equals: channel.id)
            .accessibilityLabel("Watch \(channel.name)")
            .stuckToLeadingEdge()
            .zIndex(1)

            ZStack(alignment: .topLeading) {
                Color.clear
                programmes
            }
            .frame(width: timeline.width, height: GuideMetrics.rowHeight)
        }
        .frame(height: GuideMetrics.rowHeight)
        .overlay(alignment: .bottom) { Divider() }
        .task(id: key) {
            if let key {
                grid.request(key, in: catalog.container)
            }
        }
        .onDisappear {
            if let key {
                grid.withdraw(key)
            }
        }
    }

    @ViewBuilder
    private var programmes: some View {
        if let key, let list = grid.programmes[key], !list.isEmpty {
            ForEach(list, id: \.self) { programme in
                if let frame = timeline.frame(start: programme.start, stop: programme.stop) {
                    GuideProgrammeCell(
                        channel: channel,
                        programme: programme,
                        width: frame.width,
                        action: { onSelect(programme) }
                    )
                    .offset(x: frame.x)
                }
            }
        } else if key == nil || grid.isLoaded(key ?? GuideKey(playlist: "", epgKey: "")) {
            Text("No guide for this channel")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .stayingClearOfChannelColumn(limit: .infinity)
                .padding(.leading, 12)
                .frame(height: GuideMetrics.rowHeight)
        }
    }
}

private struct GuideProgrammeCell: View {
    let channel: CatalogRow
    let programme: ProgrammeSnapshot
    let width: Double
    let action: () -> Void

    var body: some View {
        // The minute is read as the cell is drawn: a programme that ends while the grid is open is
        // dimmed the next time the row is drawn, which the grid does as it scrolls.
        let now = Date.now
        let onAir = programme.isOn(at: now)
        let over = programme.stop <= now
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(programme.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Text(Self.range(programme))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // The title stays in view while the programme's start is scrolled under the channel column.
            .stayingClearOfChannelColumn(limit: max(width - 110, 0))
            .padding(.horizontal, 8)
            .frame(width: width - 3, height: GuideMetrics.rowHeight - 6, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(onAir ? Color.blue.opacity(0.32) : Color.gray.opacity(over ? 0.10 : 0.22))
            )
            .overlay(alignment: .bottomLeading) {
                if onAir {
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: max((width - 3) * programme.fraction(at: now), 0), height: 3)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 3)
                }
            }
            .opacity(over ? 0.7 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 1.5)
        .padding(.top, 3)
        .accessibilityLabel("\(programme.title), \(Self.range(programme)), \(channel.name)")
    }

    private static func range(_ programme: ProgrammeSnapshot) -> String {
        let from = programme.start.formatted(date: .omitted, time: .shortened)
        let to = programme.stop.formatted(date: .omitted, time: .shortened)
        return "\(from) – \(to)"
    }
}

// MARK: - A programme in full

/// What a programme is, with the ways to watch the channel it is on.
private struct GuideProgrammeSheet: View {
    let selection: GuideSelection
    let onPlay: (CatalogRow) -> Void
    let onPlayTarget: (PlaybackTarget) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let programme = selection.programme
        let channel = selection.channel
        let onAir = programme.isOn(at: .now)
        let from = programme.start.formatted(date: .abbreviated, time: .shortened)
        let until = programme.stop.formatted(date: .omitted, time: .shortened)
        let when = "\(from) – \(until)"
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(programme.title).font(.title3.bold())
                        Text("\(when) · \(channel.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let subtitle = programme.subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(.callout)
                        }
                        if let details = programme.details, !details.isEmpty {
                            Text(details).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button(onAir ? "Watch now" : "Watch \(channel.name)", systemImage: "play.fill") {
                        onPlay(channel)
                    }
                    NavigationLink("Channel schedule", destination: {
                        ChannelGuideView(channel: channel, onPlay: onPlay, onPlayTarget: onPlayTarget)
                    })
                }
            }
            .navigationTitle(channel.name)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
