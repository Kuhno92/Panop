import Foundation
import PanopCore
@testable import PanopEPG
import Testing

/// Serves one canned body, cut into `chunkSize` pieces like a real connection.
private final class Transport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0
    private let status: Int
    private let body: Data
    private let chunkSize: Int
    private let failure: (any Error)?

    init(body: Data, status: Int = 200, chunkSize: Int = 64 * 1024, failure: (any Error)? = nil) {
        self.body = body
        self.status = status
        self.chunkSize = chunkSize
        self.failure = failure
    }

    convenience init(_ text: String, status: Int = 200, chunkSize: Int = 64 * 1024) {
        self.init(body: Data(text.utf8), status: status, chunkSize: chunkSize)
    }

    var requests: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(statusCode: status, body: body)
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        lock.withLock { requestCount += 1 }
        if let failure {
            throw failure
        }
        let slices = stride(from: 0, to: body.count, by: chunkSize).map {
            body.subdata(in: $0 ..< min($0 + chunkSize, body.count))
        }
        return HTTPStreamResponse(statusCode: status, chunks: HTTPChunks(slices))
    }
}

private let url = URL(string: "http://panel.example/xmltv.php?username=alice&password=s3cret") ??
    URL(fileURLWithPath: "/")

private func collect(_ batches: EPGBatches) async throws -> [[EPGElement]] {
    var result: [[EPGElement]] = []
    for try await batch in batches {
        result.append(batch)
    }
    return result
}

@Suite("EPG batches")
struct EPGBatchesTests {
    static let chunkSizes = [1, 3, 97, 64 * 1024]

    @Test(arguments: chunkSizes)
    func `reads a plain guide in batches`(chunkSize: Int) async throws {
        let transport = Transport(GuideFixture.xml(programmes: 120), chunkSize: chunkSize)
        let batches = try await collect(EPGBatches(transport: transport, url: url, batchSize: 50))

        // 1 channel + 120 programmes.
        #expect(batches.map(\.count) == [50, 50, 21])
        let programmes = batches.flatMap(\.self).filter {
            if case .programme = $0 {
                true
            } else {
                false
            }
        }
        #expect(programmes.count == 120)
    }

    /// The real-world case: an `epg.xml.gz`, decoded from zlib output, at every
    /// chunk size including one byte at a time.
    @Test(arguments: chunkSizes)
    func `reads a gzipped guide`(chunkSize: Int) async throws {
        let transport = Transport(body: GuideFixture.gzipped120, chunkSize: chunkSize)
        let plain = Transport(GuideFixture.xml(programmes: 120))

        let fromGzip = try await collect(EPGBatches(transport: transport, url: url)).flatMap(\.self)
        let fromPlain = try await collect(EPGBatches(transport: plain, url: url)).flatMap(\.self)

        #expect(fromGzip.count == 121)
        #expect(fromGzip == fromPlain)
    }

    @Test
    func `a gzipped guide is detected by content not by URL`() async throws {
        let plainURL = try #require(URL(string: "http://panel.example/guide.xml"))
        let transport = Transport(body: GuideFixture.gzipped120)
        let items = try await collect(EPGBatches(transport: transport, url: plainURL)).flatMap(\.self)
        #expect(items.count == 121)
    }

    @Test
    func `the window is applied while reading`() async throws {
        let transport = Transport(GuideFixture.xml(programmes: 120))
        let from = XMLTVDate.parse("20260929003000 +0000") ?? .distantPast
        let until = XMLTVDate.parse("20260929010000 +0000") ?? .distantFuture

        let items = try await collect(EPGBatches(transport: transport, url: url, window: from ... until))
            .flatMap(\.self)
        let titles = items.compactMap { item -> String? in
            if case let .programme(programme) = item {
                programme.title
            } else {
                nil
            }
        }
        // Show n runs from minute n to n+1: those overlapping 00:30 through 01:00.
        #expect(titles.first == "Show 29")
        #expect(titles.last == "Show 60")
    }

    @Test
    func `nothing is requested until iteration starts`() async throws {
        let transport = Transport(GuideFixture.xml(programmes: 3))
        let batches = EPGBatches(transport: transport, url: url)
        #expect(transport.requests == 0)
        _ = try await collect(batches)
        #expect(transport.requests == 1)
    }

    // MARK: - Failure

    @Test
    func `an HTTP error is reported`() async {
        await #expect(throws: EPGError.http(status: 404)) {
            _ = try await collect(EPGBatches(transport: Transport("", status: 404), url: url))
        }
    }

    @Test
    func `an HTML error page is not mistaken for a guide`() async {
        await #expect(throws: EPGError.notXMLTV) {
            _ = try await collect(EPGBatches(transport: Transport("<html>Forbidden</html>"), url: url))
        }
    }

    @Test
    func `a truncated plain guide fails`() async {
        let cut = String(GuideFixture.xml(programmes: 120).prefix(3000))
        await #expect(throws: EPGError.truncated) {
            _ = try await collect(EPGBatches(transport: Transport(cut, chunkSize: 100), url: url))
        }
    }

    /// The download dying halfway through is the case a reconcile must never
    /// treat as "these programmes were removed".
    @Test(arguments: [40, 400, 1000])
    func `a truncated gzip guide fails`(keep: Int) async {
        let cut = GuideFixture.gzipped120.prefix(keep)
        await #expect(throws: EPGError.truncated) {
            _ = try await collect(EPGBatches(transport: Transport(body: Data(cut), chunkSize: 50), url: url))
        }
    }

    @Test
    func `a corrupted gzip guide fails`() async {
        var bytes = GuideFixture.gzipped120
        bytes[bytes.count - 6] ^= 0xFF
        await #expect(throws: EPGError.corruptGzip) {
            _ = try await collect(EPGBatches(transport: Transport(body: bytes), url: url))
        }
    }

    @Test
    func `transport errors are scrubbed of credentials`() async {
        let error = NSError(
            domain: "test",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "failed for \(url.absoluteString)"]
        )
        let transport = Transport(body: Data(), failure: error)
        do {
            _ = try await collect(EPGBatches(transport: transport, url: url, redacting: ["alice", "s3cret"]))
            Issue.record("expected a throw")
        } catch let EPGError.transport(message) {
            #expect(!message.contains("s3cret"))
            #expect(!message.contains("alice"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
