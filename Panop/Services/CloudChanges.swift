import CoreData
import Foundation

/// Tells the app when changes from the person's other devices have arrived.
///
/// Only a CloudKit **import that finished and succeeded** counts. A record that is merely missing from the
/// local store (an account that was just switched, a store being rebuilt) is not news, and acting on it
/// would delete the person's playlists' data here for nothing. That is the guard against an empty or reset
/// local store pushing mass deletions: removals from another device are applied on an import event only.
nonisolated enum CloudChanges {
    static func imports(center: NotificationCenter = .default) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = Observer()
            observer.token = center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
            ) { note in
                if isFinishedImport(note) {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in
                if let token = observer.token {
                    center.removeObserver(token)
                }
            }
        }
    }

    /// Whether a CloudKit event notification reports an import that finished and succeeded.
    static func isFinishedImport(_ note: Notification) -> Bool {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event
        else { return false }
        return event.type == .import && event.endDate != nil && event.succeeded
    }

    private final class Observer: @unchecked Sendable {
        var token: NSObjectProtocol?
    }
}
