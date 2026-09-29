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
