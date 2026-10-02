import SwiftData
import SwiftUI

/// The line under a channel's name saying what is on now. Nothing at all for a channel the
/// guide does not cover, so the row stays as it was.
struct NowOnAirLine: View {
    let channel: CatalogEntryRecord

    @Environment(\.modelContext) private var catalog
    @State private var current: ProgrammeSnapshot?

    var body: some View {
        // Always present, so the row keeps one height whether or not the guide answers.
        Text(current.map { "Now: \($0.title)" } ?? " ")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .task(id: channel.id) {
                let now = Date.now
                current = GuideLookup.upcoming(
                    playlist: channel.playlist,
                    epgKey: channel.epgKey,
                    after: now,
                    limit: 1,
                    in: catalog
                ).first { $0.isOn(at: now) }
            }
    }
}

/// One channel's schedule: what is on and what follows, with a way to start watching.
struct ChannelGuideView: View {
    let channel: CatalogEntryRecord
    let onPlay: (CatalogEntryRecord) -> Void

    @Environment(\.modelContext) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var programmes: [ProgrammeSnapshot] = []
    @State private var loaded = false

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
                    }
                }
            }
        }
        .overlay {
            if loaded, programmes.isEmpty {
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
            }
    }

    private func row(_ programme: ProgrammeSnapshot) -> some View {
        let now = Date.now
        let onAir = programme.isOn(at: now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(programme.start.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
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
