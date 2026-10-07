import Foundation
import Observation
import PanopCatalog
import PanopCore
import PanopEPG
import PanopXtream

/// What the UI shows for one playlist's sync.
nonisolated enum SyncStatus: Equatable, Sendable {
    case idle
    /// `processed` counts catalog rows written so far; zero until the first batch.
    case syncing(processed: Int)
    case finished(SyncSummary)
    case failed(String)
}

nonisolated struct SyncSummary: Equatable, Sendable {
    enum Guide: Equatable, Sendable {
        case notAvailable
        case imported(programmes: Int)
        case failed
    }

    var finishedAt: Date
    /// True when the playlist file had not changed and nothing was re-imported.
    var unchanged: Bool
    var entries: Int
    var added: Int
    var removed: Int
    /// Sections that failed while others succeeded, with a readable reason.
    var failedSections: [String]
    /// Entries in the playlist left out because they had no address that could be played, for
    /// instance a relative path in a file with nothing to resolve it against.
    var skipped: Int
    /// Removals the safety check held back, waiting for the user to confirm.
    var heldBack: [DeferredRemoval]
    var guide: Guide

    init(outcome: SyncOutcome, finishedAt: Date) {
        let report = outcome.catalog
        self.finishedAt = finishedAt
        unchanged = report.outcome == .unchanged
        entries = report.kinds.reduce(0) { $0 + $1.imported }
        added = report.kinds.reduce(0) { $0 + $1.summary.inserted }
        removed = report.kinds.reduce(0) { $0 + $1.removed }
        failedSections = report.failures.map { "\(Self.name(of: $0.kind)): \($0.failure ?? "")" }
        skipped = report.skippedEntries
        heldBack = report.deferredRemovals
        switch outcome.guide {
        case .noGuideAvailable: guide = .notAvailable
        case let .imported(report): guide = .imported(programmes: report.programmes.total)
        case .failed: guide = .failed
        }
    }

    var heldBackCount: Int {
        heldBack.reduce(0) { $0 + $1.ids.count }
    }

    private static func name(of kind: MediaKind) -> String {
        switch kind {
        case .live: String(localized: "Live TV")
        case .movie: String(localized: "Movies")
        case .series: String(localized: "Series")
        case .unknown: String(localized: "Other")
        }
    }
}

/// Observable status for every playlist. Main-actor, because views read it.
@MainActor
@Observable
final class SyncStatusCenter {
    private(set) var statuses: [String: SyncStatus] = [:]

    func status(for playlist: String) -> SyncStatus {
        statuses[playlist] ?? .idle
    }

    func set(_ status: SyncStatus, for playlist: String) {
        statuses[playlist] = status
    }

    func clear(_ playlist: String) {
        statuses[playlist] = nil
    }

    /// Records that a held-back removal was carried out, so the prompt goes away.
    func resolve(_ removal: DeferredRemoval, for playlist: String) {
        guard case var .finished(summary) = statuses[playlist] else { return }
        summary.heldBack.removeAll { $0 == removal }
        summary.removed += removal.ids.count
        statuses[playlist] = .finished(summary)
    }

    var isAnySyncing: Bool {
        statuses.values.contains {
            if case .syncing = $0 {
                true
            } else {
                false
            }
        }
    }
}

/// Plain-language text for import failures.
///
/// None of it includes a URL or any server-supplied text: those can carry the
/// account's credentials.
nonisolated enum SyncErrorMessage {
    static func text(for error: Error) -> String {
        switch error {
        case let error as XtreamError: text(for: error)
        case let error as CatalogError: text(for: error)
        case let error as EPGError: text(for: error)
        default: String(localized: "Something went wrong while updating this playlist.")
        }
    }

    private static func text(for error: XtreamError) -> String {
        switch error {
        case .authenticationFailed: String(localized: "The provider rejected the username or password.")
        case .invalidBaseURL: String(localized: "That server address is not valid.")
        case let .http(status): httpText(status)
        case .unexpectedResponse: String(localized: "The provider's reply was not in the expected format.")
        case .truncatedResponse: String(localized: "The download was cut off, so nothing was changed.")
        case .transport: unreachable
        }
    }

    private static func text(for error: CatalogError) -> String {
        switch error {
        case let .http(status): httpText(status)
        case .download: unreachable
        case .cannotReadFile: String(localized: "The playlist file could not be read.")
        case .notAPlaylist: String(
                localized: "That address is a web page, not a playlist. Use the link to the file itself."
            )
        case .invalidSource: String(localized: "That is not a valid web address.")
        case .everySectionFailed: String(localized: "The provider did not return any channels, movies or series.")
        case .staleConfirmation: String(localized: "That playlist was updated in the meantime. Review it again.")
        }
    }

    private static func text(for error: EPGError) -> String {
        switch error {
        case .http, .transport: String(localized: "The TV guide could not be downloaded.")
        case .notXMLTV, .malformed: String(localized: "The TV guide is not in a format Panop understands.")
        case .truncated, .corruptGzip: String(localized: "The TV guide download was damaged, so it was not used.")
        }
    }

    private static var unreachable: String {
        String(localized: """
        Could not reach the provider. Check the address and your connection. If it is on your home network, Panop \
        needs to be allowed to use the local network, in the system settings under Privacy and Security.
        """)
    }

    private static func httpText(_ status: Int) -> String {
        switch status {
        case 401, 403: String(localized: "The provider refused access (\(status)). Check the username and password.")
        case 404: String(localized: "The provider has nothing at that address (404).")
        case 500...: String(localized: "The provider is having problems (\(status)). Try again later.")
        default: String(localized: "The provider answered with an error (\(status)).")
        }
    }
}
