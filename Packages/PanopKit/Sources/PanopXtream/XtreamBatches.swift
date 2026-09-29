import Foundation
import PanopCore

/// The rows of one list endpoint, delivered in batches as the body downloads.
///
/// Pull-based: the network is read only when the consumer asks for the next
/// batch, so a slow database write slows the download instead of letting the
/// catalog accumulate in memory. Nothing starts until iteration begins, and
/// abandoning the loop stops the download.
///
/// Rows that fail to decode (typically a missing identifier) are dropped rather
/// than failing the import: one bad row in an 80,000-row catalog should cost one
/// row.
public struct XtreamBatches<Item: Decodable & Sendable>: AsyncSequence, Sendable {
    public typealias Element = [Item]
    public typealias Failure = any Error

    let transport: any HTTPTransport
    let request: HTTPRequest
    let batchSize: Int
    let redact: @Sendable (String) -> String

    public func makeAsyncIterator() -> Iterator {
        Iterator(sequence: self)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let sequence: XtreamBatches
        private var chunks: HTTPChunks.AsyncIterator?
        private var splitter = JSONArrayStreamer()
        private var ready: [Item] = []
        private var inputDone = false
        private let decoder = JSONDecoder()

        fileprivate init(sequence: XtreamBatches) {
            self.sequence = sequence
        }

        public mutating func next() async throws -> [Item]? {
            do {
                while ready.count < sequence.batchSize, !inputDone {
                    try await readMore()
                }
            } catch let error as XtreamError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as JSONArrayStreamer.Failure {
                throw failure == .truncated ? XtreamError.truncatedResponse : XtreamError.unexpectedResponse
            } catch {
                throw XtreamError.transport(message: sequence.redact(error.localizedDescription))
            }

            guard !ready.isEmpty else { return nil }
            let take = Swift.min(sequence.batchSize, ready.count)
            let batch = Array(ready.prefix(take))
            ready.removeFirst(take)
            return batch
        }

        private mutating func readMore() async throws {
            if chunks == nil {
                let response = try await sequence.transport.stream(sequence.request)
                guard (200 ..< 300).contains(response.statusCode) else {
                    throw XtreamError.http(status: response.statusCode)
                }
                chunks = response.chunks.makeAsyncIterator()
            }

            guard var iterator = chunks, let chunk = try await iterator.next() else {
                try splitter.finish()
                inputDone = true
                return
            }
            chunks = iterator

            for raw in try splitter.consume(chunk) {
                if let item = try? decoder.decode(Item.self, from: raw) {
                    ready.append(item)
                }
            }
        }
    }
}
