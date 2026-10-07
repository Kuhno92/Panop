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
    /// Set where the guide is opened from a stream that is already playing: choosing a channel or a programme then
    /// switches that stream, instead of opening a second player.
    var onPlayChannel: ((PlaybackTarget) -> Void)?

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
    /// Apple TV only. The grid scrolls up and down by itself, and sideways by this much, kept here and not by a scroll
    /// view: the focus engine scrolls a scroll view to reveal whatever takes focus, and it did so sideways each time
    /// the focus moved to the next channel name (which is pinned to the left edge, so its layout frame is far to the
    /// left of the content), sliding the whole grid. With no sideways scroll view there is nothing to slide; the grid
    /// moves sideways only when a programme takes focus and is not fully in view (`reveal`).
    @State private var scrollX: CGFloat = 0
    /// The width the grid has on screen, for how much of the time axis is in view.
    @State private var viewportWidth: CGFloat = 1920

    var body: some View {
        let rows = narrow(list.rows)
        scrollView(rows: rows)
            .scrollPosition($position)
            .coordinateSpace(.named(GuideMetrics.space))
        #if os(tvOS)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { viewportWidth = $0 })
        #endif
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
            let start = max(0, timeline.x(for: .now) - 40)
            #if os(tvOS)
                scrollX = start
            #else
                position.scrollTo(x: start)
            #endif
        }
        .sheet(item: $selected) { selection in
            GuideProgrammeSheet(
                selection: selection,
                onPlay: { selected = nil; play($0) },
                onPlayTarget: { selected = nil; start($0) }
            )
        }
        .modifier(PlayerPresentation(target: $playing))
    }

    private func scrollView(rows: [CatalogRow]) -> some View {
        #if os(tvOS)
            ScrollView(.vertical) { gridContent(rows: rows) }
        #else
            ScrollView([.horizontal, .vertical]) { gridContent(rows: rows) }
        #endif
    }

    private func gridContent(rows: [CatalogRow]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, channel in
                    GuideGridRow(
                        channel: channel,
                        timeline: timeline,
                        grid: grid,
                        isAlternate: index.isMultiple(of: 2),
                        focus: $focusedChannel,
                        scrollX: scrollX,
                        viewportWidth: viewportWidth,
                        onReveal: reveal,
                        onPlay: play,
                        onSelect: { selected = GuideSelection(channel: channel, programme: $0) }
                    )
                    .onAppear { list.rowAppeared(channel) }
                }
            } header: {
                GuideTimeHeader(timeline: timeline, scrollX: scrollX, viewportWidth: viewportWidth)
            }
        }
        #if os(tvOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        .frame(width: GuideMetrics.channelWidth + timeline.width, alignment: .leading)
        #endif
        // Behind the rows, so the lines show through the gaps and the light cells but never over a title.
        .background(alignment: .topLeading) {
            GuideHourLines(timeline: timeline, scrollX: scrollX)
        }
    }

    /// Apple TV: brings a programme that took focus into view, sliding the time axis only as far as needed. `range` is
    /// where it lies on the axis. A programme wider than the screen is shown from its start.
    private func reveal(_ range: ClosedRange<CGFloat>) {
        let room: CGFloat = 40
        let visible = max(viewportWidth - GuideMetrics.channelWidth, 1)
        var target = scrollX
        if range.lowerBound < scrollX + room {
            target = range.lowerBound - room
        } else if range.upperBound > scrollX + visible - room {
            target = min(range.upperBound - visible + room, range.lowerBound - room)
        }
        target = min(max(0, target), max(0, timeline.width - visible))
        if abs(target - scrollX) > 0.5 {
            withAnimation(.easeOut(duration: 0.2)) { scrollX = target }
        }
    }

    private func play(_ channel: CatalogRow) {
        userState.markPlayed(channel.id)
        start(PlaybackTarget(row: channel))
    }

    private func start(_ target: PlaybackTarget) {
        if let onPlayChannel {
            onPlayChannel(target)
        } else {
            playing = target
        }
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
    /// Apple TV: how far the time axis is slid sideways, and the width of the screen.
    var scrollX: CGFloat = 0
    var viewportWidth: CGFloat = 0

    /// The time, and the day too at the first mark after midnight, so a guide that runs into tomorrow says so.
    static func label(for tick: Date) -> String {
        let time = tick.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: tick)
        guard tick.timeIntervalSince(startOfDay) < 1800 else { return time }
        return tick.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

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
            axis
        }
        .frame(height: GuideMetrics.headerHeight)
    }

    @ViewBuilder
    private var axis: some View {
        #if os(tvOS)
            axisMarks
                .offset(x: -scrollX)
                .frame(width: max(viewportWidth - GuideMetrics.channelWidth, 0), alignment: .leading)
                // Cut at the sides only: the "NOW" chip hangs below the bar and a plain clip would cut it off.
                .mask(alignment: .topLeading) {
                    Rectangle().frame(
                        width: max(viewportWidth - GuideMetrics.channelWidth, 0),
                        height: GuideMetrics.headerHeight + 40
                    )
                }
        #else
            axisMarks
        #endif
    }

    private var axisMarks: some View {
        ZStack(alignment: .topLeading) {
            GuideBarBackground()
            ForEach(timeline.ticks, id: \.self) { tick in
                let whole = GuideTimeline.isWholeHour(tick)
                Rectangle()
                    .fill(.secondary.opacity(whole ? 0.5 : 0.25))
                    .frame(width: 1, height: whole ? GuideMetrics.headerHeight : GuideMetrics.headerHeight / 2)
                    .offset(x: timeline.x(for: tick))
                Text(Self.label(for: tick))
                    .font(.caption.monospacedDigit().weight(whole ? .semibold : .regular))
                    .foregroundStyle(whole ? .primary : .secondary)
                    .padding(.leading, 6)
                    .offset(x: timeline.x(for: tick))
            }
            GuideNowChip(timeline: timeline)
        }
        .frame(width: timeline.width, height: GuideMetrics.headerHeight)
    }
}

/// Faint vertical lines at every half hour, stronger at the hour, running the height of the grid.
private struct GuideHourLines: View {
    let timeline: GuideTimeline
    /// Apple TV: how far the time axis is slid sideways.
    var scrollX: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            for tick in timeline.ticks {
                let x = GuideMetrics.channelWidth + timeline.x(for: tick) - scrollX
                let whole = GuideTimeline.isWholeHour(tick)
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.primary.opacity(whole ? 0.14 : 0.06)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small "NOW" label on the time bar, where the red line meets it.
private struct GuideNowChip: View {
    let timeline: GuideTimeline

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text("NOW")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.red))
                .offset(x: timeline.x(for: context.date) - 18, y: GuideMetrics.headerHeight - 18)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The red line at the current time, running the height of the grid.
private struct GuideNowMarker: View {
    let timeline: GuideTimeline

    var body: some View {
        TimelineView(.everyMinute) { context in
            Rectangle()
                .fill(.red)
                .frame(width: 2, height: GuideMetrics.rowHeight)
                .shadow(color: .black.opacity(0.35), radius: 1)
                .offset(x: timeline.x(for: context.date) - 1)
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
    /// Every other row is shaded a little, so a row can be followed across the grid.
    let isAlternate: Bool
    var focus: FocusState<String?>.Binding
    /// How far the time axis is slid sideways, the screen's width, and what to call when a programme takes focus (Apple
    /// TV only: see `GuideGridView.scrollX`).
    var scrollX: CGFloat = 0
    var viewportWidth: CGFloat = 0
    var onReveal: (ClosedRange<CGFloat>) -> Void = { _ in }
    let onPlay: (CatalogRow) -> Void
    let onSelect: (ProgrammeSnapshot) -> Void

    @Environment(\.modelContext) private var catalog

    private var key: GuideKey? {
        guard let epgKey = channel.epgKey, !epgKey.isEmpty else { return nil }
        return GuideKey(playlist: channel.playlist, epgKey: epgKey)
    }

    private var channelButton: some View {
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
        .guideButtonStyle(cornerRadius: 10)
        .focused(focus, equals: channel.id)
        .accessibilityLabel("Watch \(channel.name)")
    }

    private var programmeArea: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            programmes
            // Over the cells, so the line is seen across a programme, and under the channel column
            // (which is above this area), so it never crosses a channel name.
            GuideNowMarker(timeline: timeline)
        }
        .frame(width: timeline.width, height: GuideMetrics.rowHeight)
    }

    var body: some View {
        Group {
            #if os(tvOS)
                HStack(spacing: 0) {
                    channelButton
                    programmeArea
                        .offset(x: -scrollX)
                        .frame(width: max(viewportWidth - GuideMetrics.channelWidth, 0), alignment: .leading)
                        .clipped()
                }
            #else
                HStack(spacing: 0) {
                    channelButton
                        .stuckToLeadingEdge()
                        .zIndex(1)
                    programmeArea
                }
            #endif
        }
        .frame(height: GuideMetrics.rowHeight)
        .background(isAlternate ? Color.primary.opacity(0.045) : Color.clear)
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
                        action: { onSelect(programme) },
                        onFocus: { onReveal(CGFloat(frame.x) ... CGFloat(frame.x + frame.width)) }
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
    @Environment(\.colorScheme) private var scheme
    let channel: CatalogRow
    let programme: ProgrammeSnapshot
    let width: Double
    let action: () -> Void
    /// Called when the cell takes focus, for Apple TV to bring it into view.
    var onFocus: () -> Void = {}

    var body: some View {
        // The minute is read as the cell is drawn: a programme that ends while the grid is open is
        // dimmed the next time the row is drawn, which the grid does as it scrolls.
        let now = Date.now
        let onAir = programme.isOn(at: now)
        let over = programme.stop <= now
        let kind = programme.kind
        let tint = kind.color
        let shape = RoundedRectangle(cornerRadius: 8)
        Button(action: action) {
            HStack(spacing: 0) {
                // The colour of the kind, down the left edge.
                Rectangle().fill(onAir ? Color.white.opacity(0.9) : tint.opacity(over ? 0.45 : 1)).frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if onAir, width > 130 {
                            Text("NOW")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.white.opacity(0.28)))
                        }
                        Text(programme.title)
                            .font(.footnote.weight(onAir ? .bold : .semibold))
                            .lineLimit(2)
                    }
                    Text(Self.range(programme))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(onAir ? Color.white.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                }
                // The title stays in view while the programme's start is scrolled under the channel column.
                .stayingClearOfChannelColumn(limit: max(width - 110, 0))
                .padding(.horizontal, 8)
            }
            .foregroundStyle(onAir ? Color.white : Color.primary)
            .frame(width: width - 3, height: GuideMetrics.rowHeight - 6, alignment: .leading)
            .background(shape.fill(Self.fill(tint: tint, onAir: onAir, over: over, dark: scheme == .dark)))
            .clipShape(shape)
            // What is on now is ringed, so it stands out from everything round it.
            .overlay(shape.strokeBorder(
                onAir ? Color.white.opacity(0.9) : tint.opacity(over ? 0.10 : 0.30), lineWidth: onAir ? 2 : 1
            ))
            .overlay(alignment: .bottomLeading) {
                if onAir {
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule().fill(.white).frame(width: max((width - 3 - 16) * programme.fraction(at: now), 4))
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
            .shadow(color: onAir ? tint.opacity(0.45) : .clear, radius: 5, y: 1)
            .opacity(over ? 0.7 : 1)
            .contentShape(Rectangle())
        }
        .guideButtonStyle(cornerRadius: 8, onFocus: onFocus)
        .padding(.leading, 1.5)
        .padding(.top, 3)
        .accessibilityLabel("\(programme.title), \(Self.range(programme)), \(channel.name)")
        .accessibilityValue(onAir ? Text("NOW") : Text(kind.title))
    }

    /// Strong for what is on, a light wash of the kind's colour for what is coming, fainter for what is over.
    private static func fill(tint: Color, onAir: Bool, over: Bool, dark: Bool) -> AnyShapeStyle {
        if onAir {
            return AnyShapeStyle(LinearGradient(
                colors: [tint, tint.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        // A wash that is enough to tell the kind on a dark screen, where the same tint is muddier.
        return AnyShapeStyle(tint.opacity(over ? (dark ? 0.12 : 0.07) : (dark ? 0.30 : 0.17)))
    }

    private static func range(_ programme: ProgrammeSnapshot) -> String {
        let from = programme.start.formatted(date: .omitted, time: .shortened)
        let to = programme.stop.formatted(date: .omitted, time: .shortened)
        return "\(from) – \(to)"
    }
}
