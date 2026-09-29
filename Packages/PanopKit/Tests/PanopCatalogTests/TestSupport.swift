import Foundation
import PanopCatalog
import PanopCore
import PanopEPG

/// Answers requests from a closure, streaming bodies in small chunks like a
/// real connection.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) throws -> (status: Int, body: String)

    private let handler: Handler
    private let chunkSize: Int

    init(chunkSize: Int = 4096, handler: @escaping Handler) {
        self.chunkSize = chunkSize
        self.handler = handler
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (status, body) = try handler(request)
        return HTTPResponse(statusCode: status, body: Data(body.utf8))
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let (status, body) = try handler(request)
        let bytes = Array(body.utf8)
        let slices = stride(from: 0, to: bytes.count, by: chunkSize).map {
            Data(bytes[$0 ..< min($0 + chunkSize, bytes.count)])
        }
        return HTTPStreamResponse(statusCode: status, chunks: HTTPChunks(slices))
    }
}

/// Returns the value of a query parameter.
func query(_ request: HTTPRequest, _ name: String) -> String? {
    URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == name }?.value
}

// MARK: - Playlist files

/// Writes text to a temporary file and returns its path.
func writeTemporaryFile(_ text: String) throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("panop-test-\(UUID().uuidString).m3u")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

/// A playlist of live channels, `count` long, ids starting at `from`.
func livePlaylist(_ range: Range<Int>, group: String = "News", epgURL: String? = nil) -> String {
    var lines = [epgURL.map { #"#EXTM3U url-tvg="\#($0)""# } ?? "#EXTM3U"]
    for index in range {
        lines
            .append(
                #"#EXTINF:-1 tvg-id="Chan.\#(index)" tvg-logo="http://img/\#(index).png" group-title="\#(group)",Channel \#(index)"#
            )
        lines.append("http://host/live/u/p/\(index).ts")
    }
    return lines.joined(separator: "\n") + "\n"
}

// MARK: - A store that fails on demand

/// Forwards to an in-memory store, but throws from the Nth entry upsert on.
/// Simulates a database error, or a cancelled import, part-way through.
actor FlakyStore: CatalogStore {
    struct Failure: Error {}

    let base = InMemoryCatalogStore()
    private var upserts = 0
    private let failFrom: Int

    init(failFromUpsert: Int) {
        failFrom = failFromUpsert
    }

    func upsertEntries(_ entries: [CatalogEntry], playlist: String) async throws -> UpsertSummary {
        upserts += 1
        if upserts >= failFrom {
            throw Failure()
        }
        return try await base.upsertEntries(entries, playlist: playlist)
    }

    func entryCount(kind: MediaKind, playlist: String) async throws -> Int {
        await base.entryCount(kind: kind, playlist: playlist)
    }

    func entryIDs(kind: MediaKind, playlist: String, after: String?, limit: Int) async throws -> [String] {
        await base.entryIDs(kind: kind, playlist: playlist, after: after, limit: limit)
    }

    func removeEntries(ids: [String], playlist: String) async throws {
        await base.removeEntries(ids: ids, playlist: playlist)
    }

    func upsertCategories(_ categories: [CatalogCategory], playlist: String) async throws {
        await base.upsertCategories(categories, playlist: playlist)
    }

    func categoryIDs(kind: MediaKind, playlist: String) async throws -> [String] {
        await base.categoryIDs(kind: kind, playlist: playlist)
    }

    func removeCategories(ids: [String], kind: MediaKind, playlist: String) async throws {
        await base.removeCategories(ids: ids, kind: kind, playlist: playlist)
    }

    func upsertEPGChannels(_ channels: [EPGChannel], playlist: String) async throws {
        await base.upsertEPGChannels(channels, playlist: playlist)
    }

    func upsertProgrammes(_ programmes: [EPGProgramme], playlist: String) async throws -> UpsertSummary {
        await base.upsertProgrammes(programmes, playlist: playlist)
    }

    func programmeCount(playlist: String, endingAfter: Date) async throws -> Int {
        await base.programmeCount(playlist: playlist, endingAfter: endingAfter)
    }

    func programmeKeys(
        playlist: String,
        endingAfter: Date,
        after: ProgrammeKey?,
        limit: Int
    ) async throws -> [ProgrammeKey] {
        await base.programmeKeys(playlist: playlist, endingAfter: endingAfter, after: after, limit: limit)
    }

    func removeProgrammes(keys: [ProgrammeKey], playlist: String) async throws {
        await base.removeProgrammes(keys: keys, playlist: playlist)
    }

    func removeProgrammes(endedBefore date: Date, playlist: String) async throws -> Int {
        await base.removeProgrammes(endedBefore: date, playlist: playlist)
    }

    func syncState(playlist: String) async throws -> SyncState? {
        await base.syncState(playlist: playlist)
    }

    func saveSyncState(_ state: SyncState, playlist: String) async throws {
        await base.saveSyncState(state, playlist: playlist)
    }
}
