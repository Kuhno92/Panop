import Foundation

/// What the Live TV screen should say, from what has happened to each source.
///
/// Kept apart from the view so the cases that matter can be tested: a source that failed
/// must not read as "no channels", and a source that is still working must not read as a
/// failure. `nonisolated`, because it is plain data.
nonisolated enum LiveEmptyState: Equatable {
    struct Source: Equatable {
        var id: String
        var name: String
        var status: SyncStatus
    }

    struct Problem: Equatable, Identifiable {
        var id: String
        var name: String
        var message: String
    }

    /// Nothing to show and nothing wrong: the person has not added anything yet.
    case noPlaylists
    case searchFoundNothing
    /// Channels are still being fetched.
    case syncing
    /// The channels could not be fetched, and why.
    case failed([Problem])
    /// The source loaded and holds no live channels, for instance a movies-only account.
    case noLiveChannels

    /// - Parameters:
    ///   - sources: the sources the screen is showing: the chosen one, or all.
    ///   - hasPlaylists: whether any playlist exists at all, chosen or not.
    static func resolve(isSearching: Bool, sources: [Source], hasPlaylists: Bool) -> LiveEmptyState {
        if isSearching {
            return .searchFoundNothing
        }
        guard hasPlaylists, !sources.isEmpty else {
            return .noPlaylists
        }
        if sources.contains(where: \.status.isSyncing) {
            return .syncing
        }
        let problems = problems(in: sources)
        return problems.isEmpty ? .noLiveChannels : .failed(problems)
    }

    /// The sources whose last update failed, with the reason in plain words.
    static func problems(in sources: [Source]) -> [Problem] {
        sources.compactMap { source in
            guard case let .failed(message) = source.status else { return nil }
            return Problem(id: source.id, name: source.name, message: message)
        }
    }
}

nonisolated extension SyncStatus {
    var isSyncing: Bool {
        if case .syncing = self {
            true
        } else {
            false
        }
    }
}
