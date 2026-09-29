import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData

/// A catalog store on a real SQLite file in its own directory.
///
/// On disk rather than in memory on purpose: an in-memory store evaluates
/// sorting and comparison in Swift, so it cannot show a collation or paging
/// bug, which is exactly what these tests exist to catch.
struct OnDiskCatalog {
    let directory: URL
    let container: ModelContainer
    let store: SwiftDataCatalogStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("panop-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try PanopContainers.makeCatalog(storeURL: directory.appendingPathComponent("catalog.store"))
        store = SwiftDataCatalogStore(container: container)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Answers requests from a closure, streaming bodies in small chunks.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) throws -> (status: Int, body: String)

    private let handler: Handler
    private let chunkSize: Int

    init(chunkSize: Int = 8192, handler: @escaping Handler) {
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

func entry(_ id: String, kind: MediaKind = .live, name: String? = nil, group: String? = nil) -> CatalogEntry {
    CatalogEntry(id: id, kind: kind, name: name ?? "Name \(id)", groupID: group, groupName: group)
}

func writeTemporaryFile(_ text: String) throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("panop-test-\(UUID().uuidString).m3u")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

/// A playlist of `count` live channels and `movies` movies.
func playlistText(live: Range<Int>, movies: Range<Int> = 0 ..< 0, group: String = "News") -> String {
    var lines = ["#EXTM3U"]
    for index in live {
        lines
            .append(
                #"#EXTINF:-1 tvg-id="Chan.\#(index)" tvg-logo="http://img/\#(index).png" group-title="\#(group)",Channel \#(index)"#
            )
        lines.append("http://host/live/u/p/\(index).ts")
    }
    for index in movies {
        lines.append(#"#EXTINF:-1 group-title="Movies",Movie \#(index)"#)
        lines.append("http://host/movie/u/p/\(index).mkv")
    }
    return lines.joined(separator: "\n") + "\n"
}

// MARK: - App services

/// An Xtream panel that answers the given lists.
struct FakePanel {
    var live = 3
    var movies = 2
    var series = 0
    var loginBody = #"{"user_info":{"auth":1,"status":"Active"}}"#
    var guideBody: String?
    var unreachable = false

    func transport() -> StubTransport {
        let panel = self
        return StubTransport { request in
            if panel.unreachable {
                throw URLError(.notConnectedToInternet)
            }
            if request.url.path.hasSuffix("xmltv.php") {
                return panel.guideBody.map { (200, $0) } ?? (404, "")
            }
            switch URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "action" })?.value
            {
            case nil: return (200, panel.loginBody)
            case "get_live_streams": return (200, panel.list(panel.live, id: "stream_id", name: "Live"))
            case "get_vod_streams": return (200, panel.list(panel.movies, id: "stream_id", name: "Movie"))
            case "get_series": return (200, panel.list(panel.series, id: "series_id", name: "Show"))
            default: return (200, "[]")
            }
        }
    }

    private func list(_ count: Int, id: String, name: String) -> String {
        "[" + (0 ..< count).map { #"{"\#(id)":\#($0),"name":"\#(name) \#($0)"}"# }.joined(separator: ",") + "]"
    }
}

/// The whole service graph over an on-disk catalog and an in-memory cloud
/// container, with credentials that never touch the real Keychain.
@MainActor
struct TestApp {
    let services: AppServices
    let catalog: OnDiskCatalog
    let cloud: ModelContainer
    let credentials: InMemoryCredentialStore
    let directory: URL

    init(transport: any HTTPTransport, credentials: InMemoryCredentialStore = InMemoryCredentialStore()) throws {
        catalog = try OnDiskCatalog()
        cloud = try PanopContainers.makeCloud(inMemory: true)
        self.credentials = credentials
        directory = catalog.directory.appendingPathComponent("Playlists")
        services = AppServices(
            catalog: catalog.container,
            cloud: cloud,
            credentials: credentials,
            transport: transport,
            playlistsDirectory: directory
        )
    }

    /// The persisted playlist records, read through a context of their own, so
    /// tests see what was actually stored rather than what the library reports.
    func storedRecords() throws -> [PlaylistRecord] {
        try ModelContext(cloud).fetch(FetchDescriptor<PlaylistRecord>())
    }

    func cleanUp() {
        catalog.cleanUp()
    }
}

/// Wraps a transport that can be switched to hang, so a sync stays in flight
/// (until cancelled) while a test acts on it.
final class SwitchableTransport: HTTPTransport, @unchecked Sendable {
    private let base: any HTTPTransport
    private let lock = NSLock()
    private var hanging = false

    init(_ base: any HTTPTransport) {
        self.base = base
    }

    func setHanging(_ value: Bool) {
        lock.withLock { hanging = value }
    }

    private var isHanging: Bool {
        lock.withLock { hanging }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if isHanging {
            try await Task.sleep(for: .seconds(3600))
        }
        return try await base.send(request)
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        if isHanging {
            try await Task.sleep(for: .seconds(3600))
        }
        return try await base.stream(request)
    }
}
