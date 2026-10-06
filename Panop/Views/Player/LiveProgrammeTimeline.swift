import SwiftUI

/// What is on the channel now and until when, with a bar for how far through it is, and what comes next: the guide
/// in the player's controls, in place of the scrubber a live channel does not have.
///
/// Answered from `GuideNowStore`, the same memory the channel list reads, so a channel just picked from the list
/// shows its programme in the first frame. Looked at again every quarter of a minute, which moves the bar and turns
/// the programme over when it ends.
struct LiveProgrammeTimeline: View {
    let guide: GuideKey

    @Environment(\.guideNow) private var store
    @Environment(\.modelContext) private var catalog

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(at: context.date)
                .onChange(of: context.date) { ask() }
        }
        .task(id: guide) { ask() }
    }

    private func ask() {
        store.request(playlist: guide.playlist, epgKey: guide.epgKey, in: catalog.container)
    }

    @ViewBuilder
    private func content(at moment: Date) -> some View {
        if let now = store.current(playlist: guide.playlist, epgKey: guide.epgKey, now: moment) {
            let next = store.next(playlist: guide.playlist, epgKey: guide.epgKey, now: moment)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(now.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    (Text(now.start, format: .dateTime.hour().minute())
                        + Text(verbatim: " – ")
                        + Text(now.stop, format: .dateTime.hour().minute()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize()
                }
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * now.fraction(at: moment))
                        }
                    }
                    .accessibilityHidden(true)
                if let next {
                    Text("Next: \(next.start.formatted(date: .omitted, time: .shortened)) · \(next.title)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The gap to the buttons is here, not in the parent, so a channel with no guide leaves no gap.
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("liveProgramme")
        }
    }
}
