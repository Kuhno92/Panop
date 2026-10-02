import Foundation
import PanopCore
import PanopXtream

/// A playlist to sync, as the importer needs it. Deliberately plain values: the
/// app resolves secrets from its own storage and hands them in here.
public struct PlaylistDescriptor: Sendable, Equatable {
    public var id: String
    public var source: PlaylistSource
    /// A guide URL the user supplied. Used for M3U sources whose header does not
    /// advertise one. Xtream panels always use their own `xmltv.php`.
    public var guideURL: String?
    /// What to call the channel if the source turns out to be a single stream.
    public var name: String?
    /// False for a source added to carry live TV only: its movies and series are not fetched,
    /// parsed or stored. For an Xtream panel that saves two of the three large downloads.
    public var includeVOD: Bool

    public init(
        id: String,
        source: PlaylistSource,
        guideURL: String? = nil,
        name: String? = nil,
        includeVOD: Bool = true
    ) {
        self.id = id
        self.source = source
        self.guideURL = guideURL
        self.name = name
        self.includeVOD = includeVOD
    }
}

public enum GuideOutcome: Sendable, Equatable {
    case imported(EPGImportReport)
    /// The playlist advertises no guide and none was configured.
    case noGuideAvailable
    /// The guide failed. The catalog import is unaffected.
    case failed(String)
}

public struct SyncOutcome: Sendable, Equatable {
    public var catalog: ImportReport
    public var guide: GuideOutcome

    public init(catalog: ImportReport, guide: GuideOutcome) {
        self.catalog = catalog
        self.guide = guide
    }
}

/// How much of a guide to keep.
///
/// Import time scales with the rows kept, and a provider's 7 to 14 day guide is
/// mostly never viewed. Two hours back (for a programme already under way) and
/// two days ahead is what a guide screen and channel banners actually read.
public enum GuideWindow {
    public static let lookBack: TimeInterval = 2 * 3600
    public static let lookAhead: TimeInterval = 48 * 3600

    public static func standard(around now: Date) -> ClosedRange<Date> {
        now.addingTimeInterval(-lookBack) ... now.addingTimeInterval(lookAhead)
    }
}

/// What the catalog half of a sync produced, and what the guide half needs.
private struct CatalogImportResult {
    var report: ImportReport
    var guideURL: URL?
    /// Strings to scrub from any error raised while fetching the guide.
    var secrets: [String]
}

extension CatalogImporter {
    /// Imports a playlist and then its guide.
    ///
    /// The two are independent: a guide that fails, is missing or is cut off
    /// never fails or undoes the catalog import, and is reported in the outcome.
    ///
    /// - Parameters:
    ///   - guide: pass false to leave the guide alone, for instance when it was
    ///     refreshed recently.
    ///   - force: import an M3U file even when its digest is unchanged.
    /// - Throws: anything the catalog import throws. Nothing is thrown for the
    ///   guide, except cancellation.
    public func sync(
        _ playlist: PlaylistDescriptor,
        window: ClosedRange<Date>? = nil,
        guide: Bool = true,
        force: Bool = false
    ) async throws -> SyncOutcome {
        let imported = try await importCatalog(playlist, force: force)
        let report = imported.report
        guard guide, let guideURL = imported.guideURL else {
            return SyncOutcome(catalog: report, guide: .noGuideAvailable)
        }

        do {
            let guideReport = try await importEPG(
                playlist: playlist.id,
                url: guideURL,
                window: window ?? GuideWindow.standard(around: now()),
                redacting: imported.secrets
            )
            return SyncOutcome(catalog: report, guide: .imported(guideReport))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return SyncOutcome(catalog: report, guide: .failed(String(describing: error)))
        }
    }

    private func importCatalog(
        _ playlist: PlaylistDescriptor,
        force: Bool
    ) async throws -> CatalogImportResult {
        switch playlist.source {
        case let .remoteM3U(text):
            guard let url = Self.httpURL(text) else { throw CatalogError.invalidSource }
            var secrets = URLSecrets.values(in: url)
            let report = try await importM3U(
                playlist: playlist.id,
                source: .remote(url, redacting: secrets),
                force: force,
                streamName: playlist.name,
                includeVOD: playlist.includeVOD
            )
            let guideURL = Self.guideURL(advertised: report.epgURLs, configured: playlist.guideURL)
            secrets += guideURL.map(URLSecrets.values(in:)) ?? []
            return CatalogImportResult(report: report, guideURL: guideURL, secrets: secrets)

        case let .localM3U(path):
            let report = try await importM3U(
                playlist: playlist.id,
                source: .file(path: path),
                force: force,
                streamName: playlist.name,
                includeVOD: playlist.includeVOD
            )
            let guideURL = Self.guideURL(advertised: report.epgURLs, configured: playlist.guideURL)
            return CatalogImportResult(
                report: report,
                guideURL: guideURL,
                secrets: guideURL.map(URLSecrets.values(in:)) ?? []
            )

        case let .xtream(credentials):
            let report = try await importXtream(
                playlist: playlist.id,
                credentials: credentials,
                includeVOD: playlist.includeVOD
            )
            let guideURL = try XtreamClient(credentials: credentials, transport: transport).guideURL()
            return CatalogImportResult(
                report: report,
                guideURL: guideURL,
                secrets: [credentials.username, credentials.password]
            )
        }
    }

    /// A header may list several guides; the user's own setting wins.
    private static func guideURL(advertised: [String], configured: String?) -> URL? {
        ([configured].compactMap(\.self) + advertised).lazy.compactMap(httpURL).first
    }

    private static func httpURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false
        else { return nil }
        return url
    }
}

/// Pulls credential-looking values out of a URL, so error messages built from
/// it can be scrubbed. Credentials appear as user-info and in query values.
enum URLSecrets {
    static func values(in url: URL) -> [String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        var values = [components.user, components.password].compactMap(\.self)
        values += (components.queryItems ?? []).compactMap(\.value)
        return values.filter { !$0.isEmpty }
    }
}
