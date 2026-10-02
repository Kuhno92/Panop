import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A request as the core sees it. Deliberately not `URLRequest`, so the
/// protocol below can be implemented on platforms where `URLSession` is not
/// the network stack.
public struct HTTPRequest: Sendable, Equatable {
    public var url: URL
    public var headers: [String: String]
    public var timeout: TimeInterval
    /// `GET` unless a call to an API says otherwise.
    public var method: String
    public var body: Data?

    public init(
        url: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 60,
        method: String = "GET",
        body: Data? = nil
    ) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
        self.method = method
        self.body = body
    }
}

/// A fully buffered response. Only for bodies known to be small.
public struct HTTPResponse: Sendable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// A response body delivered in chunks, **pulled** by the consumer.
///
/// This is not an `AsyncThrowingStream` on purpose. A stream buffers whatever
/// the producer yields without limit, so a slow consumer (a database write)
/// would not slow the network read and the whole catalog would pile up in
/// memory. Here nothing is read until `next()` asks for it.
public struct HTTPChunks: AsyncSequence, Sendable {
    public typealias Element = Data
    public typealias Failure = any Error

    private let makePull: @Sendable () -> () async throws -> Data?

    /// - Parameter makePull: called once per iteration, returns the function
    ///   that produces the next chunk, or `nil` at the end.
    public init(makePull: @escaping @Sendable () -> () async throws -> Data?) {
        self.makePull = makePull
    }

    /// A fixed list of chunks. Used by tests and by transports that already
    /// hold the whole body.
    public init(_ chunks: [Data]) {
        self.init {
            var index = 0
            return {
                guard index < chunks.count else { return nil }
                defer { index += 1 }
                return chunks[index]
            }
        }
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate var pull: () async throws -> Data?

        public mutating func next() async throws -> Data? {
            try await pull()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(pull: makePull())
    }
}

/// A response whose body arrives in chunks.
///
/// Catalogs and guides run to hundreds of megabytes, so anything that can be
/// large is consumed through this rather than ``HTTPTransport/send(_:)``.
public struct HTTPStreamResponse: Sendable {
    public var statusCode: Int
    public var chunks: HTTPChunks

    public init(statusCode: Int, chunks: HTTPChunks) {
        self.statusCode = statusCode
        self.chunks = chunks
    }
}

/// All network access in the portable core goes through this.
///
/// Linux can supply an AsyncHTTPClient implementation and tests supply a stub,
/// without any orchestration code changing.
///
/// Implementations must not put the request URL into a thrown error. Provider
/// URLs carry credentials, and errors end up in logs.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse
}

/// `URLSession`-backed transport.
public struct URLSessionTransport: HTTPTransport {
    /// Size of the slices handed to consumers when streaming.
    private static let chunkSize = 64 * 1024

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private func urlRequest(for request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = urlRequest(for: request)
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let http = response as? HTTPURLResponse {
                        continuation.resume(returning: HTTPResponse(statusCode: http.statusCode, body: data ?? Data()))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    #if canImport(FoundationNetworking)
        /// swift-corelibs-foundation has no incremental byte stream, so off-Apple
        /// this buffers the body and slices it. Correct, but not flat in memory.
        /// A platform that needs flat memory should supply its own transport.
        public func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
            let response = try await send(request)
            let body = response.body
            let slices = stride(from: 0, to: body.count, by: Self.chunkSize).map {
                body.subdata(in: $0 ..< min($0 + Self.chunkSize, body.count))
            }
            return HTTPStreamResponse(statusCode: response.statusCode, chunks: HTTPChunks(slices))
        }
    #else
        public func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
            let (bytes, response) = try await session.bytes(for: urlRequest(for: request))
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            let size = Self.chunkSize
            let chunks = HTTPChunks {
                var iterator = bytes.makeAsyncIterator()
                return {
                    var buffer = Data()
                    buffer.reserveCapacity(size)
                    while let byte = try await iterator.next() {
                        buffer.append(byte)
                        if buffer.count >= size {
                            return buffer
                        }
                    }
                    return buffer.isEmpty ? nil : buffer
                }
            }
            return HTTPStreamResponse(statusCode: http.statusCode, chunks: chunks)
        }
    #endif
}

/// Lets a cancellation handler reach a task that is only created inside the
/// continuation body.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock()
        defer { lock.unlock() }
        self.task = task
        if cancelled {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }
}
