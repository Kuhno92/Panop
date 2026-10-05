import PanopPlayback
import SwiftUI

/// How playback has behaved on this device: how fast channels start, how often they stall, and
/// which engines did the work. Local only, and nothing in it names a channel or an address.
struct PlaybackStatisticsView: View {
    @Environment(\.playbackMetrics) private var store

    @State private var statistics: PlaybackStatistics?
    @State private var confirmingClear = false

    var body: some View {
        Form {
            if let statistics, statistics.sessions > 0 {
                summary(statistics)
                engines(statistics)
                Section {
                    Button("Clear Statistics", role: .destructive) { confirmingClear = true }
                } footer: {
                    Text("Kept on this device only, for the last \(PlaybackMetricsStore.capacity) viewing sessions.")
                }
            } else {
                ContentUnavailableView(
                    "Nothing yet",
                    systemImage: "chart.bar",
                    description: Text("Watch something and its numbers show up here.")
                )
            }
        }
        .pageBackdrop()
        .navigationTitle("Playback Statistics")
        .task { statistics = await store?.statistics() }
        .confirmationDialog("Clear the statistics?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                Task {
                    await store?.clear()
                    statistics = await store?.statistics()
                }
            }
        }
    }

    private func summary(_ stats: PlaybackStatistics) -> some View {
        Section("Overall") {
            LabeledContent("Viewing sessions", value: stats.sessions.formatted())
            LabeledContent("Time to first picture, typical", value: seconds(stats.medianJoinSeconds))
            LabeledContent("Time to first picture, slowest tenth", value: seconds(stats.p90JoinSeconds))
            LabeledContent("Time spent waiting for data", value: percent(stats.rebufferRatio))
            LabeledContent("Left before a picture", value: percent(stats.leftBeforeFirstFrame))
            LabeledContent("Needed another player", value: percent(stats.fellBack))
            LabeledContent("Could not be played at all", value: percent(stats.failed))
        }
    }

    @ViewBuilder
    private func engines(_ stats: PlaybackStatistics) -> some View {
        if !stats.byEngine.isEmpty {
            Section("By player") {
                ForEach(stats.byEngine, id: \.engine) { share in
                    LabeledContent(share.engine.displayName) {
                        Text("\(share.sessions.formatted()) · \(seconds(share.medianJoinSeconds))")
                    }
                }
            }
        }
    }

    private func seconds(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value < 1 ? "\(Int((value * 1000).rounded())) ms" : String(format: "%.1f s", value)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(value < 0.1 ? 1 : 0)))
    }
}
