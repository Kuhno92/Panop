import Foundation
import Network
@testable import Panop
import PanopCore
import VLCKit

/// Real MPEG-TS, for tests of the case that decides whether fallback is worth having:
/// a raw transport stream over HTTP, which AVPlayer cannot read and which is how most
/// IPTV providers serve live channels.
///
/// The stream is muxed by libVLC's own stream output from generated H.264 video, so
/// no external tool is needed and nothing is committed.
enum TransportStreamFixture {
    @MainActor private static var cached: Data?

    /// The stream, made once and reused: muxing takes a few seconds and every test
    /// wants the same bytes.
    @MainActor
    static func shared() async throws -> Data {
        if let cached {
            return cached
        }
        let data = try await make()
        cached = data
        return data
    }

    /// Video muxed into MPEG-TS, and the bytes of it.
    @MainActor
    static func make(seconds: Double = 3) async throws -> Data {
        let source = try await writeVideo(seconds: seconds)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).ts")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        guard let media = VLCMedia(url: source) else { throw TransportStreamError.notATransportStream(bytes: 0) }
        media.addOption(":sout=#std{access=file,mux=ts,dst=\(destination.path)}")
        // Held so that its release happens off the main thread (see VLCPlayerHolder).
        let holder = VLCPlayerHolder()
        // Swift may release `holder` after its last use, which would stop the player.
        defer { withExtendedLifetime(holder) {} }
        let player = holder.player
        player.media = media
        player.play()

        // The stream output writes as the input plays through. libVLC does not
        // reliably report "stopped" for a stream-output run, so the file is judged
        // finished when it has stopped growing.
        let deadline = ContinuousClock.now + .seconds(30)
        var lastSize = -1
        var stableFor = 0
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
            stableFor = (size == lastSize && size > 188 * 20) ? stableFor + 1 : 0
            lastSize = size
            if stableFor >= 8 {
                break
            }
        }
        try await Task.sleep(for: .milliseconds(200))

        let data = try Data(contentsOf: destination)
        guard data.count > 188 * 10, data[0] == 0x47 else {
            throw TransportStreamError.notATransportStream(bytes: data.count)
        }
        return data
    }
}

enum TransportStreamError: Error {
    case notATransportStream(bytes: Int)
}

/// A one-purpose HTTP server on the loopback interface. It answers any request with
/// the given body and no `Content-Length`, then closes, which is how a live IPTV
/// endpoint looks to a player.
final class LocalStreamServer: @unchecked Sendable {
    private let listener: NWListener
    private let body: Data
    private let contentType: String
    private let holdOpen: Bool
    private let queue = DispatchQueue(label: "panop.test.stream-server")
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    /// - Parameter holdOpen: keep sending the body in a loop, like a live channel.
    ///   Otherwise the server sends it once and closes after a moment, which a player
    ///   reports as the stream ending.
    init(body: Data, contentType: String = "video/mp2t", holdOpen: Bool = false) throws {
        listener = try NWListener(using: .tcp, on: .any)
        self.body = body
        self.contentType = contentType
        self.holdOpen = holdOpen
    }

    /// Sends the body over and over until the connection goes, as a live channel keeps
    /// coming. A player probing a stream that has simply stopped waits out its read
    /// timeout before it gives up on finding more, so a quiet connection is not a live one.
    private static func stream(_ body: Data, after head: Data?, to connection: NWConnection) {
        connection.send(
            content: (head ?? Data()) + body,
            contentContext: .defaultMessage,
            isComplete: false,
            completion: .contentProcessed { error in
                if error == nil {
                    stream(body, after: nil, to: connection)
                }
            }
        )
    }

    /// Starts listening and returns the address to fetch from.
    func start() async throws -> URL {
        let contentType = contentType
        let body = body
        let holdOpen = holdOpen
        listener.newConnectionHandler = { [weak self] connection in
            self?.lock.withLock { self?.connections.append(connection) }
            connection.start(queue: DispatchQueue.global())
            // Read the request line and headers, whatever they are, then answer.
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                let head = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nConnection: close\r\n\r\n"
                if holdOpen {
                    Self.stream(body, after: Data(head.utf8), to: connection)
                    return
                }
                connection.send(
                    content: Data(head.utf8) + body,
                    contentContext: .finalMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in
                        // Closing at once can reset the connection while the client is
                        // still reading, which FFmpeg reports as an I/O error rather
                        // than the end of the stream. Give it time to take the bytes.
                        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                            connection.cancel()
                        }
                    }
                )
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = ResumeOnce()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue, resumed.take() {
                        continuation
                            .resume(returning: URL(string: "http://127.0.0.1:\(port)/live/channel.ts") ??
                                URL(fileURLWithPath: "/"))
                    }
                case let .failed(error):
                    if resumed.take() {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        lock.withLock { connections.forEach { $0.cancel() } }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func take() -> Bool {
        lock.withLock {
            if done {
                return false
            }
            done = true
            return true
        }
    }
}
