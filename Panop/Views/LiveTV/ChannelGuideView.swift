import PanopCore
import PanopXtream
import SwiftData
import SwiftUI

/// The two lines under a channel's name: what is on now, and what comes next. Nothing at all for a
/// channel with no guide key, so its row stays as it was.
struct NowOnAirLine: View {
    let channel: CatalogRow

    @Environment(\.guideNow) private var store
    @Environment(\.modelContext) private var catalog

    var body: some View {
        if channel.epgKey?.isEmpty == false {
            // Answered from memory. The programmes are read in the background and the lines fill in when
            // they arrive; until then they hold their height, so the row does not move. Looked at
            // again every minute, so the line changes as a programme ends and the next begins, and
            // reads again once what was known has run out.
            TimelineView(.everyMinute) { timeline in
                lines(at: timeline.date)
                    .onChange(of: timeline.date) {
                        store.request(playlist: channel.playlist, epgKey: channel.epgKey, in: catalog.container)
                    }
            }
            .task(id: channel.id) {
                store.request(playlist: channel.playlist, epgKey: channel.epgKey, in: catalog.container)
            }
            .onDisappear { store.withdraw(playlist: channel.playlist, epgKey: channel.epgKey) }
        }
    }

    private func lines(at moment: Date) -> some View {
        let current = store.current(playlist: channel.playlist, epgKey: channel.epgKey, now: moment)
        let next = store.next(playlist: channel.playlist, epgKey: channel.epgKey, now: moment)
        let tint = current?.kind.color ?? .clear
        // The guide's grid in miniature, with nothing to scroll: what is on and how far through it is, then
        // what follows in the colour of its kind. Every part holds its height when empty, so a row does not
        // move as the guide fills in.
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(current.map { "Now: \($0.title)" } ?? " ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let current {
                    Text("\(String(Self.minutesLeft(current, at: moment))) min left")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Capsule()
                .fill(tint.opacity(current == nil ? 0 : 0.2))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(tint).frame(width: proxy.size.width * (current?.fraction(at: moment) ?? 0))
                    }
                }
            Text(next.map { "Next: \($0.start.formatted(date: .omitted, time: .shortened)) · \($0.title)" } ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill((next?.kind.color ?? .clear).opacity(next == nil ? 0 : 0.16)))
        }
    }

    private static func minutesLeft(_ programme: ProgrammeSnapshot, at moment: Date) -> Int {
        max(1, Int((programme.stop.timeIntervalSince(moment) / 60).rounded(.up)))
    }
}

/// One channel's schedule: what is on and what follows, with a way to start watching.
struct ChannelGuideView: View {
    let channel: CatalogRow
    let onPlay: (CatalogRow) -> Void
    let onPlayTarget: (PlaybackTarget) -> Void

    @Environment(PlaylistLibrary.self) private var library
    @Environment(\.modelContext) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var programmes: [ProgrammeSnapshot] = []
    @State private var aired: [ProgrammeSnapshot] = []
    @State private var loaded = false
    /// The panel's time zone, learned when the guide opens, for the archive's addresses.
    @State private var panelTimeZone: String?
    @State private var catchupFailed = false

    /// A day's worth is plenty to browse; more is a longer scroll with nothing to decide.
    private static let limit = 60

    var body: some View {
        List {
            Section {
                Button("Watch \(channel.name)", systemImage: "play.fill") {
                    dismiss()
                    onPlay(channel)
                }
            }
            if !programmes.isEmpty {
                Section("Schedule") {
                    ForEach(programmes) { programme in
                        row(programme)
                            // What is on now is tinted in its kind's colour, so it is found at a glance.
                            .listRowBackground(programme.isOn(at: .now) ? programme.kind.color.opacity(0.16) : nil)
                    }
                }
            }
            if !aired.isEmpty {
                Section {
                    ForEach(aired) { programme in
                        Button { watch(programme) } label: {
                            row(programme).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Watch from the start")
                    }
                } header: {
                    Text("Earlier")
                } footer: {
                    if catchupFailed {
                        Text("The provider could not be reached for this programme.")
                    } else {
                        Text("Tap a programme to watch it from the start.")
                    }
                }
            }
        }
        .pageBackdrop()
        .overlay {
            if loaded, programmes.isEmpty, aired.isEmpty {
                ContentUnavailableView(
                    "No guide for this channel",
                    systemImage: "calendar",
                    description: Text("The source has no programme information for it.")
                )
            }
        }
        .navigationTitle(channel.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                programmes = GuideLookup.upcoming(
                    playlist: channel.playlist,
                    epgKey: channel.epgKey,
                    limit: Self.limit,
                    in: catalog
                )
                loaded = true
                await loadArchive()
            }
    }

    // MARK: - Catch-up

    /// A channel the panel archives: the programmes that aired within its window, and the
    /// panel's time zone to address them in. Xtream only: an M3U playlist's catch-up is a
    /// template that differs from provider to provider.
    private func loadArchive() async {
        guard channel.hasArchive, let days = channel.archiveDays, days > 0,
              case let .xtream(credentials)? = try? library.descriptor(for: channel.playlist)?.source
        else { return }
        aired = GuideLookup.aired(
            playlist: channel.playlist,
            epgKey: channel.epgKey,
            days: days,
            limit: Self.limit,
            in: catalog
        )
        guard !aired.isEmpty,
              let client = try? XtreamClient(credentials: credentials, transport: URLSessionTransport())
        else { return }
        panelTimeZone = try? await client.authenticate().timeZoneID
    }

    private func watch(_ programme: ProgrammeSnapshot) {
        var target = PlaybackTarget(row: channel)
        target.name = "\(channel.name) · \(programme.title)"
        target.catchup = CatchupWindow(
            start: programme.start,
            minutes: Int((programme.stop.timeIntervalSince(programme.start) / 60).rounded(.up)),
            timeZoneID: panelTimeZone
        )
        dismiss()
        onPlayTarget(target)
    }

    private func row(_ programme: ProgrammeSnapshot) -> some View {
        let now = Date.now
        let onAir = programme.isOn(at: now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(programme.start.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Circle().fill(programme.kind.color).frame(width: 9, height: 9).accessibilityHidden(true)
                Text(programme.title).font(.body.weight(onAir ? .semibold : .regular))
                if onAir {
                    Text("NOW").font(.caption2.bold()).foregroundStyle(.red)
                }
            }
            if let subtitle = programme.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            if onAir {
                ProgressView(value: programme.fraction(at: now))
                    .accessibilityLabel("Progress")
            }
            if let details = programme.details, !details.isEmpty {
                Text(details).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}
