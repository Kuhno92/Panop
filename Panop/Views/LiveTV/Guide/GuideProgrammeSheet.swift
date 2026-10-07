import SwiftUI

// MARK: - A programme in full

/// What a programme is, with the ways to watch the channel it is on.
struct GuideProgrammeSheet: View {
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
            .pageBackdrop()
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

#if !os(tvOS)
    /// A button that explains the colours: what each kind of programme is drawn in, and how what is on now is shown.
    private struct GuideColourKeyButton: View {
        @State private var showing = false

        var body: some View {
            Button("Colour key", systemImage: "paintpalette") { showing = true }
                .popover(isPresented: $showing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Colour key").font(.headline)
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(
                                    colors: [.blue, .blue.opacity(0.78)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: 2))
                                .frame(width: 26, height: 18)
                            Text("On now")
                        }
                        ForEach(ProgrammeCategory.allCases, id: \.self) { kind in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(kind.color.opacity(0.17))
                                    .overlay(alignment: .leading) { Rectangle().fill(kind.color).frame(width: 4) }
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .frame(width: 26, height: 18)
                                Text(kind.title)
                            }
                        }
                    }
                    .padding()
                    .presentationCompactAdaptation(.popover)
                }
        }
    }
#endif
