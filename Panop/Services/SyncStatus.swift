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
        case .live: "Live TV"
        case .movie: "Movies"
        case .series: "Series"
        case .unknown: "Other"
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
        default: "Something went wrong while updating this playlist."
        }
    }

    private static func text(for error: XtreamError) -> String {
        switch error {
        case .authenticationFailed: "The provider rejected the username or password."
        case .invalidBaseURL: "That server address is not valid."
        case let .http(status): httpText(status)
        case .unexpectedResponse: "The provider's reply was not in the expected format."
        case .truncatedResponse: "The download was cut off, so nothing was changed."
        case .transport: unreachable
        }
    }

    private static func text(for error: CatalogError) -> String {
        switch error {
        case let .http(status): httpText(status)
        case .download: unreachable
        case .cannotReadFile: "The playlist file could not be read."
        case .invalidSource: "That is not a valid web address."
        case .everySectionFailed: "The provider did not return any channels, movies or series."
        case .staleConfirmation: "That playlist was updated in the meantime. Review it again."
        }
    }

    private static func text(for error: EPGError) -> String {
        switch error {
        case .http, .transport: "The TV guide could not be downloaded."
        case .notXMLTV, .malformed: "The TV guide is not in a format Panop understands."
        case .truncated, .corruptGzip: "The TV guide download was damaged, so it was not used."
        }
    }

    private static let unreachable = "Could not reach the provider. Check the address and your connection."

    private static func httpText(_ status: Int) -> String {
        switch status {
        case 401, 403: "The provider refused access (\(status)). Check the username and password."
        case 404: "The provider has nothing at that address (404)."
        case 500...: "The provider is having problems (\(status)). Try again later."
        default: "The provider answered with an error (\(status))."
        }
    }
}
