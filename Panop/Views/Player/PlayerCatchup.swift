import SwiftData
import SwiftUI

/// Catch-up over a playing channel: the programmes of the last days that the provider keeps, to play one from its
/// start. It is the channel's own guide screen, which lists them under "Earlier", in a sheet (on Apple TV the whole
/// screen). Choosing a programme, or the channel live, hands it back to the player.
struct PlayerCatchupPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let channel: PlaybackTarget
    let onPlay: (PlaybackTarget) -> Void

    @Environment(\.modelContext) private var catalog

    func body(content: Content) -> some View {
        #if os(tvOS)
            content.fullScreenCover(isPresented: $isPresented) { screen }
        #else
            content.sheet(isPresented: $isPresented) {
                screen
                #if os(macOS)
                    .frame(minWidth: 520, minHeight: 480)
                #endif
            }
        #endif
    }

    @ViewBuilder
    private var screen: some View {
        if let row {
            NavigationStack {
                ChannelGuideView(
                    channel: row,
                    onPlay: { onPlay(PlaybackTarget(row: $0)) },
                    onPlayTarget: onPlay,
                    catchupFirst: true
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { isPresented = false }
                    }
                }
            }
        }
    }

    /// The channel as the catalog holds it: the guide screen is written for a list's row.
    private var row: CatalogRow? {
        let playlist = channel.playlist
        let id = channel.entryID
        var descriptor = FetchDescriptor<CatalogEntryRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? catalog.fetch(descriptor))?.first.map(CatalogRow.init)
    }
}
