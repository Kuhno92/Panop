import PanopCore
import SwiftUI

/// Which version of a grouped channel to play, from what is known of its versions.
@MainActor
enum ChannelVersions {
    /// The channels that share this one's guide key, in the provider's order, without any the person has hidden. Empty
    /// until they are read, and for a channel with no guide key.
    static func usable(_ channel: CatalogRow, store: ChannelVariantsStore, userState: UserStateStore) -> [CatalogRow] {
        guard let all = store.variants(playlist: channel.playlist, groupKey: channel.groupKey) else { return [] }
        return all.filter { $0.entryID == channel.entryID || !userState.hidden.contains($0.id) }
    }

    /// The version to play when the channel is chosen: the one the person picked last time, else the channel itself.
    static func chosen(for channel: CatalogRow, among versions: [CatalogRow], userState: UserStateStore) -> CatalogRow {
        guard versions.count > 1, let groupKey = channel.groupKey,
              let id = userState.preferredVariant(playlist: channel.playlist, epgKey: groupKey),
              let match = versions.first(where: { $0.entryID == id })
        else { return channel }
        return match
    }

    /// Remembers the person's pick for next time.
    static func remember(_ version: CatalogRow, userState: UserStateStore) {
        guard let groupKey = version.groupKey, !groupKey.isEmpty else { return }
        userState.setPreferredVariant(version.entryID, playlist: version.playlist, epgKey: groupKey)
    }
}

/// The button at the end of a grouped channel's row that offers its versions: the HD and the SD, say. Nothing for a
/// channel with a single version, or when the list is not grouped.
struct ChannelVersionsMenu: View {
    let channel: CatalogRow
    let onPlay: (CatalogRow) -> Void

    @Environment(\.channelVariants) private var store
    @Environment(UserStateStore.self) private var userState
    @AppStorage(ChannelGrouping.key) private var groupsByGuide = ChannelGrouping.isOnByDefault

    var body: some View {
        let versions = groupsByGuide ? ChannelVersions.usable(channel, store: store, userState: userState) : []
        if versions.count > 1 {
            let current = ChannelVersions.chosen(for: channel, among: versions, userState: userState)
            Menu {
                ForEach(versions) { version in
                    Button {
                        ChannelVersions.remember(version, userState: userState)
                        onPlay(version)
                    } label: {
                        if version.entryID == current.entryID {
                            Label(version.name, systemImage: "checkmark")
                        } else {
                            Text(version.name)
                        }
                    }
                }
            } label: {
                VersionsChip(count: versions.count)
            }
            .accessibilityLabel("Choose a version")
            .accessibilityValue(Text(current.name))
            .accessibilityIdentifier("channelVersions")
            #if os(tvOS)
                .buttonStyle(BareRowButtonStyle())
                .focusEffectDisabled()
            #endif
        }
    }
}

#if os(tvOS)
    /// A button with nothing of its own, not even the system's focus effect: the plain style still lifts and lights the
    /// button on Apple TV. The row draws the highlight (`ChannelListRow`).
    struct BareRowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }
#endif

/// The versions button as a small pill: the number of versions beside a stack of squares. On Apple TV it has no system
/// highlight (the row draws its own, round the pill too): it goes dark when it is the one with focus.
private struct VersionsChip: View {
    let count: Int
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Label("\(count)", systemImage: "square.stack.3d.up")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isFocused ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isFocused ? Color.black.opacity(0.85) : Color.primary.opacity(0.12)))
    }
}

/// One channel's row: choosing it plays, and a channel with several versions has a button for them at its end.
///
/// On Apple TV the highlight of the focused row is drawn here, across the whole row, the versions button included. The
/// system's highlight stopped where the row's own button did, a stretch short of the row's end, and a row without
/// versions was longer than one with.
struct ChannelListRow<Label: View>: View {
    let channel: CatalogRow
    let play: () -> Void
    let playVersion: (CatalogRow) -> Void
    @ViewBuilder let label: () -> Label

    #if os(tvOS)
        private enum Part: Hashable {
            case row, versions
        }

        @FocusState private var focus: Part?
        @Environment(\.colorScheme) private var scheme
    #endif

    var body: some View {
        #if os(tvOS)
            let lit = focus != nil
            HStack(spacing: 8) {
                Button(action: play) { label().contentShape(Rectangle()) }
                    .buttonStyle(BareRowButtonStyle())
                    .focusEffectDisabled()
                    .focused($focus, equals: .row)
                ChannelVersionsMenu(channel: channel, onPlay: playVersion)
                    .focused($focus, equals: .versions)
            }
            // Dark text on the light highlight, as the system's highlight does.
            .environment(\.colorScheme, lit ? .light : scheme)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(lit ? 0.92 : 0))
            }
            .scaleEffect(lit ? 1.015 : 1)
            .animation(.easeOut(duration: 0.12), value: lit)
        #else
            HStack(spacing: 8) {
                Button(action: play) { label().contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                ChannelVersionsMenu(channel: channel, onPlay: playVersion)
                    .buttonStyle(.plain)
            }
        #endif
    }
}
