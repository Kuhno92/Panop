import SwiftUI

/// The days to choose from as one strip across the whole screen: a few back for results, today marked, and a week and
/// more ahead. It scrolls, and keeps the chosen day in the middle.
struct DayTimeline: View {
    @Binding var selection: Int
    let today: Date

    @Environment(\.calendar) private var calendar

    private static var pillWidth: CGFloat {
        #if os(tvOS)
            104
        #else
            58
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(SportsHubModel.dayRange), id: \.self) { offset in
                        pill(offset)
                            .id(offset)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            #if os(tvOS)
            .scrollClipDisabled()
            // One section across the strip: Down from a day lands on the hero whatever its width, and Up from the hero
            // returns to a day, not to the buttons at the edge.
            .focusSection()
            #endif
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, new in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func date(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func pill(_ offset: Int) -> some View {
        let day = date(offset)
        let chosen = offset == selection
        return Button { selection = offset } label: {
            VStack(spacing: 3) {
                Text(offset == 0 ? String(localized: "Today") : day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(day.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(day.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2)
                    .opacity(0.7)
            }
            .foregroundStyle(chosen ? Color.black : .white)
            .frame(width: Self.pillWidth)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(chosen ? Color.liveGreen : .white.opacity(0.09))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("day\(offset)")
    }
}
