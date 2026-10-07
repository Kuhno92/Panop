import Foundation

/// What the first screen of an empty device says about iCloud: whether it is looking for the person's other devices,
/// has found playlists there, has found nothing yet, or cannot look at all.
///
/// Pure, so the wording each case leads to is decided in one place and tested without a screen.
nonisolated enum SyncWelcomePhase: Equatable {
    /// Playlists arrived from another device and wait for the person to say they are wanted.
    case offer(names: [String])
    /// iCloud is on and answering is awaited.
    case searching
    /// iCloud is on and nothing came within the time given.
    case nothingFound
    /// iCloud cannot be used right now, and why.
    case unavailable(CloudSync.Availability)
    /// Nothing to say about iCloud: the plain welcome.
    case plain

    /// How long a fresh device waits for its other devices before saying nothing has come. An import is usually a
    /// matter of seconds, but a device that was never opened with the account can take longer.
    static let patience: Duration = .seconds(30)

    static func phase(availability: CloudSync.Availability, offer: [String]?, waited: Bool) -> SyncWelcomePhase {
        if let offer {
            return .offer(names: offer)
        }
        switch availability {
        case .active:
            return waited ? .nothingFound : .searching
        case .noAccount, .notEntitled, .failed:
            return .unavailable(availability)
        case .off, .testing:
            return .plain
        }
    }
}
