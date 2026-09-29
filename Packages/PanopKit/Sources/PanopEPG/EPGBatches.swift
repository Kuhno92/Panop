import Foundation
import PanopCore

/// A guide read over the network, delivered in batches as it downloads.
///
/// Handles both plain XMLTV and gzip. Compression is detected from the first
/// two bytes rather than the URL or headers, because `URLSession` silently
/// undoes `Content-Encoding: gzip` but not a `.xml.gz` file, and providers do
/// both.
///
/// Pull-based, like ``XtreamBatches``: the network is read only when the
/// consumer asks for the next batch, so a slow database write slows the
/// download and a 150 MB guide never accumulates in memory. Nothing starts
/// until iteration begins, and abandoning the loop stops the download.
///
/// Throws ``EPGError/truncated`` or ``EPGError/corruptGzip`` for a damaged
/// download. Never treat those as "the provider removed these programmes".
/// How a guide body is compressed, decided from its first bytes.
private enum BodyEncoding { case plain, gzip }

public struct EPGBatches: AsyncSequence, Sendable {
    public typealias Element = [EPGElement]
    public typealias Failure = any Error

    private let transport: any HTTPTransport
    private let request: HTTPRequest
    private let window: ClosedRange<Date>?
    private let batchSize: Int
    private let secrets: [String]

    /// - Parameters:
    ///   - window: keep only programmes that overlap this range.
    ///   - secrets: strings scrubbed from error messages, typically the
    ///     account's username and password when they are part of the URL.
    public init(
        transport: any HTTPTransport,
        url: URL,
        window: ClosedRange<Date>? = nil,
        batchSize: Int = 1000,
        redacting secrets: [String] = []
    ) {
        self.transport = transport
        request = HTTPRequest(url: url, timeout: 120)
        self.window = window
        self.batchSize = Swift.max(1, batchSize)
        self.secrets = secrets.filter { !$0.isEmpty }
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(sequence: self)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let sequence: EPGBatches
        private var chunks: HTTPChunks.AsyncIterator?
        private var parser: XMLTVParser
        private var gzip = GzipDecoder()
        private var encoding: BodyEncoding?
        private var sniffed = Data()
        private var ready: [EPGElement] = []
        private var inputDone = false

        fileprivate init(sequence: EPGBatches) {
            self.sequence = sequence
            parser = XMLTVParser(window: sequence.window)
        }

        public mutating func next() async throws -> [EPGElement]? {
            do {
                while ready.count < sequence.batchSize, !inputDone {
                    try await readMore()
                }
            } catch let error as EPGError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as GzipDecoder.Failure {
                throw failure == .truncated ? EPGError.truncated : EPGError.corruptGzip
            } catch {
                throw EPGError.transport(message: redact(error.localizedDescription))
            }

            guard !ready.isEmpty else { return nil }
            let take = Swift.min(sequence.batchSize, ready.count)
            let batch = Array(ready.prefix(take))
            ready.removeFirst(take)
            return batch
        }

        // MARK: - Reading

        private mutating func readMore() async throws {
            if chunks == nil {
                let response = try await sequence.transport.stream(sequence.request)
                guard (200 ..< 300).contains(response.statusCode) else {
                    throw EPGError.http(status: response.statusCode)
                }
                chunks = response.chunks.makeAsyncIterator()
            }

            guard var iterator = chunks, let chunk = try await iterator.next() else {
                try finishInput()
                inputDone = true
                return
            }
            chunks = iterator
            try feed(chunk)
        }

        private mutating func feed(_ chunk: Data) throws {
            var data = chunk
            if encoding == nil {
                // Two bytes decide the encoding, and a chunk can hold fewer.
                sniffed.append(chunk)
                guard sniffed.count >= 2 else { return }
                let magic = Array(sniffed.prefix(2))
                encoding = magic == [0x1F, 0x8B] ? .gzip : .plain
                data = sniffed
                sniffed = Data()
            }
            if encoding == .gzip {
                data = try gzip.consume(data)
            }
            ready += try parser.consume(data)
        }

        private mutating func finishInput() throws {
            if encoding == nil {
                // Fewer than two bytes in total: cannot be a gzip stream.
                encoding = .plain
                ready += try parser.consume(sniffed)
            }
            if encoding == .gzip {
                try gzip.finish()
            }
            try parser.finish()
        }

        private func redact(_ text: String) -> String {
            sequence.secrets.reduce(text) { $0.replacingOccurrences(of: $1, with: "<redacted>") }
        }
    }
}
