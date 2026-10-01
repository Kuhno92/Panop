import Foundation
import VLCKit

/// Turns libVLC's connection failures into something an engine can act on.
///
/// For a stream it cannot reach, libVLC logs the reason, fires no error event, and
/// stays "opening" for good. The coordinator then waits out its whole start timeout
/// and reports a dropped connection, when the connection never existed. Found with an
/// HTTPS stream whose TLS handshake libVLC could not complete (docs/engines.md).
///
/// libVLC's logger is library-wide, not per player, so a failure cannot be traced to
/// one engine. It goes to every engine still opening: there is normally one, and a
/// wrong guess costs a fallback, never a wrong picture.
///
/// `nonisolated`, and not `final`, for the same modifier-order reason as the bridge.
nonisolated class VLCConnectionWatch: NSObject, VLCLogging, @unchecked Sendable {
    nonisolated static let shared = VLCConnectionWatch()

    nonisolated(unsafe) var level: VLCLogLevel = .error

    /// Messages that mean the stream cannot be reached at all.
    private static let fatal = ["HTTP connection failure", "TLS session handshake error"]

    private struct Entry {
        weak var engine: VLCEngine?
    }

    private let lock = NSLock()
    private var engines: [Entry] = []
    private var installed = false

    /// Starts listening, once. libVLC takes its loggers in one assignment, so any
    /// others (a test's file logger) must come through here, and before the first engine.
    func install(alongside others: [any VLCLogging] = []) {
        lock.withLock {
            guard !installed else { return }
            installed = true
            VLCLibrary.shared().loggers = others + [self]
        }
    }

    func add(_ engine: VLCEngine) {
        lock.withLock {
            engines.removeAll { $0.engine == nil || $0.engine === engine }
            engines.append(Entry(engine: engine))
        }
    }

    func remove(_ engine: VLCEngine) {
        lock.withLock { engines.removeAll { $0.engine == nil || $0.engine === engine } }
    }

    func handleMessage(_ message: String, logLevel: VLCLogLevel, context: VLCLogContext?) {
        guard Self.fatal.contains(where: message.contains) else { return }
        let watching = lock.withLock { engines.compactMap(\.engine) }
        guard !watching.isEmpty else { return }
        let box = UncheckedBox(watching)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                box.value.forEach { $0.connectionFailed(message) }
            }
        }
    }
}
