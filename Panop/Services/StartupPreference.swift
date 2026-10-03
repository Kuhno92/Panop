import Foundation
import SwiftData

/// What the app does when it opens, as the person chose it in Settings.
nonisolated enum StartupAction: String, CaseIterable, Identifiable, Sendable {
    case home, live, movies, series
    /// Straight into a chosen live channel.
    case channel

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .live: String(localized: "Live TV")
        case .movies: String(localized: "Movies")
        case .series: String(localized: "Series")
        case .channel: String(localized: "Play a channel")
        }
    }

    /// Movies and Series are not offered when no source has any.
    var needsVOD: Bool {
        self == .movies || self == .series
    }
}

/// The settings keys and what they come to on a given launch.
nonisolated enum StartupPreference {
    static let actionKey = "startupAction"
    static let channelKey = "startupChannelKey"
    static let channelNameKey = "startupChannelName"

    /// Where to open, and which channel to start, if any.
    struct Plan: Equatable, Sendable {
        var tab: AppTab
        /// `UserStateStore.key(playlist:entry:)` of the channel to play at once.
        var channel: String?
    }

    /// Never a plan that cannot be carried out: a screen that is not offered is Home, and
    /// "play a channel" with none chosen is just Live TV.
    static func plan(action: StartupAction, channel: String, offersVOD: Bool) -> Plan {
        switch action {
        case .home: Plan(tab: .home, channel: nil)
        case .live: Plan(tab: .live, channel: nil)
        case .movies: Plan(tab: offersVOD ? .movies : .home, channel: nil)
        case .series: Plan(tab: offersVOD ? .series : .home, channel: nil)
        case .channel: Plan(tab: .live, channel: channel.isEmpty ? nil : channel)
        }
    }

    /// The plan for the stored settings.
    static func current(offersVOD: Bool, defaults: UserDefaults = .standard) -> Plan {
        plan(
            action: StartupAction(rawValue: defaults.string(forKey: actionKey) ?? "") ?? .home,
            channel: defaults.string(forKey: channelKey) ?? "",
            offersVOD: offersVOD
        )
    }
}

extension StartupPreference {
    /// The channel a stored key names, from the catalog already on disk. Nil once it has gone.
    ///
    /// An entry id can repeat across playlists, so the playlist is checked as well.
    @MainActor
    static func channel(for key: String, in context: ModelContext) -> CatalogEntryRecord? {
        let entryID = UserStateStore.entryID(in: key)
        var descriptor = FetchDescriptor<CatalogEntryRecord>(predicate: #Predicate { $0.id == entryID })
        descriptor.fetchLimit = 50
        return (try? context.fetch(descriptor))?.first {
            UserStateStore.key(playlist: $0.playlist, entry: $0.id) == key
        }
    }
}
