import Foundation
import PanopCore

/// Decides whether a sweep may delete what it found stale.
///
/// A download that was cut short looks exactly like a smaller catalog. An M3U
/// file has no end marker and arrives chunked without a length, so the parser
/// cannot tell. A sweep that trusted it would delete everything past the cut,
/// including favourites and watch progress keyed to those rows. So a sweep
/// that would remove a large share of the catalog is held back, reported, and
/// only carried out on explicit confirmation.
public struct PrunePolicy: Sendable, Equatable {
    /// Removing more than this fraction of the previous catalog is held back.
    public var maxRemovedFraction: Double
    /// Removals up to this many rows are always allowed. Small playlists
    /// change by whole percentages routinely, and the harm is bounded.
    public var alwaysAllowUpTo: Int

    public init(maxRemovedFraction: Double = 0.5, alwaysAllowUpTo: Int = 25) {
        self.maxRemovedFraction = maxRemovedFraction
        self.alwaysAllowUpTo = alwaysAllowUpTo
    }

    func allows(removing count: Int, of previous: Int) -> Bool {
        count <= alwaysAllowUpTo || Double(count) <= Double(previous) * maxRemovedFraction
    }
}

/// A removal the safety check refused to do on its own.
public struct DeferredRemoval: Sendable, Equatable {
    public var kind: MediaKind
    public var ids: [String]
    /// The playlist's import counter when this was produced. Confirming after a
    /// newer import is refused: that import may have brought these rows back.
    public var importCounter: Int

    public init(kind: MediaKind, ids: [String], importCounter: Int) {
        self.kind = kind
        self.ids = ids
        self.importCounter = importCounter
    }
}

/// What happened to one media kind during an import.
public struct KindReport: Sendable, Equatable {
    public var kind: MediaKind
    public var imported: Int
    public var summary: UpsertSummary
    public var removed: Int
    public var deferredRemoval: DeferredRemoval?
    /// Set when this section failed. Nothing is removed for a failed section.
    public var failure: String?

    public init(
        kind: MediaKind,
        imported: Int = 0,
        summary: UpsertSummary = UpsertSummary(),
        removed: Int = 0,
        deferredRemoval: DeferredRemoval? = nil,
        failure: String? = nil
    ) {
        self.kind = kind
        self.imported = imported
        self.summary = summary
        self.removed = removed
        self.deferredRemoval = deferredRemoval
        self.failure = failure
    }
}

public struct ImportReport: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case imported
        /// The file's digest matched the last completed import, so nothing ran.
        case unchanged
    }

    public var outcome: Outcome
    public var kinds: [KindReport]
    /// Guide URLs the playlist advertises, for the caller to feed to
    /// ``CatalogImporter/importEPG(playlist:url:window:redacting:)``.
    public var epgURLs: [String]
    /// Entries left out because they had no playable address. Not a failure, but
    /// worth telling the user about: a playlist that is mostly this is probably not
    /// the address they meant.
    public var skippedEntries: Int

    public init(outcome: Outcome, kinds: [KindReport] = [], epgURLs: [String] = [], skippedEntries: Int = 0) {
        self.outcome = outcome
        self.kinds = kinds
        self.epgURLs = epgURLs
        self.skippedEntries = skippedEntries
    }

    public var failures: [KindReport] {
        kinds.filter { $0.failure != nil }
    }

    public var deferredRemovals: [DeferredRemoval] {
        kinds.compactMap(\.deferredRemoval)
    }
}

public struct EPGImportReport: Sendable, Equatable {
    public var channels: Int
    public var programmes: UpsertSummary
    public var removedStale: Int
    public var removedExpired: Int
    /// Stale programmes the safety check declined to remove. They age out on
    /// their own, so there is nothing to confirm.
    public var deferredStale: Int

    public init(
        channels: Int = 0,
        programmes: UpsertSummary = UpsertSummary(),
        removedStale: Int = 0,
        removedExpired: Int = 0,
        deferredStale: Int = 0
    ) {
        self.channels = channels
        self.programmes = programmes
        self.removedStale = removedStale
        self.removedExpired = removedExpired
        self.deferredStale = deferredStale
    }
}

/// Progress for a UI to show while an import runs.
public struct ImportProgress: Sendable, Equatable {
    /// Nil while reading a guide.
    public var kind: MediaKind?
    public var processed: Int

    public init(kind: MediaKind?, processed: Int) {
        self.kind = kind
        self.processed = processed
    }
}

/// Failures of the import itself. No case carries a URL or credentials.
public enum CatalogError: Error, Equatable, Sendable {
    case http(status: Int)
    /// The download failed. Credentials are scrubbed from the message.
    case download(message: String)
    case cannotReadFile
    /// What came back is a web page, not a playlist, such as GitHub's page about a file and not the file.
    case notAPlaylist
    /// The playlist's source is not something that can be fetched, such as a
    /// malformed URL.
    case invalidSource
    /// Every section of an Xtream import failed, so there is nothing to keep.
    case everySectionFailed(firstFailure: String)
    /// The confirmation refers to an import that is no longer the latest.
    case staleConfirmation
}
