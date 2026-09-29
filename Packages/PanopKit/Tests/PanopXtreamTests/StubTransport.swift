import Foundation
import PanopCore

/// Serves canned responses and records what was asked, with no network.
///
/// Streamed bodies are cut into `chunkSize` pieces so tests exercise the
/// chunk-boundary handling that a real connection would.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) throws -> (status: Int, body: String)

    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private let handler: Handler
    private let chunkSize: Int

    init(chunkSize: Int = 64 * 1024, handler: @escaping Handler) {
        self.chunkSize = chunkSize
        self.handler = handler
    }

    /// One fixed body for every request.
    convenience init(chunkSize: Int = 64 * 1024, status: Int = 200, body: String) {
        self.init(chunkSize: chunkSize) { _ in (status, body) }
    }

    var requests: [HTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// The value of a query parameter on the most recent request.
    func lastQuery(_ name: String) -> String? {
        guard let url = requests.last?.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    private func record(_ request: HTTPRequest) {
        lock.lock()
        recorded.append(request)
        lock.unlock()
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        record(request)
        let (status, body) = try handler(request)
        return HTTPResponse(statusCode: status, body: Data(body.utf8))
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        record(request)
        let (status, body) = try handler(request)
        let bytes = Array(body.utf8)
        let slices = stride(from: 0, to: bytes.count, by: chunkSize).map {
            Data(bytes[$0 ..< min($0 + chunkSize, bytes.count)])
        }
        return HTTPStreamResponse(statusCode: status, chunks: HTTPChunks(slices))
    }
}
