import Foundation
import Observation
import PanopSimkl

/// How a finished item is known to Simkl.
nonisolated enum SimklTracking: Hashable, Sendable {
    case movie(tmdb: Int)
    case episode(showTMDB: Int, season: Int, number: Int)
}

/// Sends what the person finishes to their Simkl account, in batches, never on a timer.
///
/// Event-driven: nothing is sent until something is finished, then one call carries everything waiting.
/// What could not be sent stays in a file and goes with the next batch, so being offline loses nothing.
/// Only finished items are recorded: Simkl marks a title watched on a record, and resume points stay on
/// this device.
@MainActor
@Observable
final class SimklSync {
    static let enabledKey = "simklSendWatched"
    /// Quiet time before sending, so the episodes marked in a row go as one call.
    static let settleDelay = Duration.seconds(5)
    /// Before trying again after a failure, and the longest it grows to.
    static let retryDelay = Duration.seconds(120)

    typealias Send = @Sendable ([SimklWatched]) async throws -> Void

    private(set) var queued: [SimklWatched]
    var isEnabled = true

    private let send: Send
    private let queueURL: URL?
    private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private var known: [String: SimklTracking] = [:]
    @ObservationIgnored private var flushing: Task<Void, Never>?

    init(
        queueURL: URL? = SimklSync.defaultQueueURL,
        send: @escaping Send,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.queueURL = queueURL
        self.send = send
        self.sleep = sleep
        queued = Self.load(queueURL)
    }

    isolated deinit {
        flushing?.cancel()
    }

    /// Says what a key is on Simkl, for when it is finished. Cheap; called as titles are opened.
    func register(_ key: String, as tracking: SimklTracking?) {
        known[key] = tracking
    }

    /// The person finished `key`, by watching to the end or marking it.
    func finished(_ key: String, at date: Date = .now) {
        guard isEnabled, let tracking = known[key] else { return }
        let item: SimklWatched = switch tracking {
        case let .movie(tmdb): .movie(tmdb: tmdb, at: date)
        case let .episode(show, season, number): .episode(showTMDB: show, season: season, number: number, at: date)
        }
        guard !queued.contains(where: { Self.sameTitle($0, item) }) else { return }
        queued.append(item)
        save()
        scheduleFlush(after: Self.settleDelay)
    }

    /// Sends what is waiting, if anything. Called when the app starts and after a sign-in.
    func flushIfNeeded() {
        guard isEnabled, !queued.isEmpty else { return }
        scheduleFlush(after: .zero)
    }

    /// Drops what is waiting, for when the person disconnects: it was theirs to send to that account.
    func discardQueue() {
        flushing?.cancel()
        flushing = nil
        queued = []
        save()
    }

    private func scheduleFlush(after delay: Duration) {
        flushing?.cancel()
        flushing = Task { [weak self] in
            await self?.sleep(delay)
            await self?.flush()
        }
    }

    private func flush() async {
        guard !Task.isCancelled, !queued.isEmpty else { return }
        let batch = queued
        do {
            try await send(batch)
            queued.removeAll { item in batch.contains { $0 == item } }
            save()
            // More may have been finished while this was in flight.
            if !queued.isEmpty {
                scheduleFlush(after: Self.settleDelay)
            }
        } catch SimklError.unauthorized {
            // Signed out: nothing to retry until they sign in again, which calls `flushIfNeeded`.
        } catch {
            scheduleFlush(after: Self.retryDelay)
        }
    }

    private static func sameTitle(_ lhs: SimklWatched, _ rhs: SimklWatched) -> Bool {
        identity(lhs) == identity(rhs)
    }

    /// Which title an item is, without when it was watched.
    private static func identity(_ item: SimklWatched) -> String {
        switch item {
        case let .movie(tmdb, _): "m\(tmdb)"
        case let .episode(show, season, number, _): "e\(show).\(season).\(number)"
        }
    }

    // MARK: - File

    private func save() {
        guard let queueURL else { return }
        if queued.isEmpty {
            try? FileManager.default.removeItem(at: queueURL)
            return
        }
        try? FileManager.default.createDirectory(
            at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(queued) {
            try? data.write(to: queueURL, options: .atomic)
        }
    }

    private static func load(_ url: URL?) -> [SimklWatched] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SimklWatched].self, from: data)) ?? []
    }

    nonisolated static var defaultQueueURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Simkl", isDirectory: true)
            .appendingPathComponent("queue.json")
    }
}
