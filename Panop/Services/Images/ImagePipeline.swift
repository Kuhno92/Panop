import CoreGraphics
import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Loads, caches and downsamples images, for the thousands of channel logos a catalog holds.
///
/// Built around what makes a long list of small images go wrong:
///
/// - **Decoding at the displayed size**, never the downloaded size (`ImageDownsampler`).
/// - **A memory cache with a byte budget**, emptied on a memory warning and when the app goes
///   to the background. On tvOS an app over budget is killed, with no warning.
/// - **A disk cache with a size limit**, so scrolling back, and the next launch, cost no
///   network (`DiskImageCache`).
/// - **One download per image**, however many rows ask: a list re-renders and the same logo is
///   asked for again and again.
/// - **A cap on downloads in flight**, newest first, so a fast scroll fetches what is on screen
///   now and not what was on screen a second ago.
/// - **Cancellation that follows the rows.** A download nobody is waiting for any more stops.
/// - **Remembering a failure** for a while, so a dead logo is not requested again on every draw.
actor ImagePipeline {
    typealias Fetch = @Sendable (URL) async throws -> Data

    struct Limits {
        var memoryBytes: Int
        var maxImageBytes = 4_000_000
        var maxConcurrentDownloads = 4
        var failureMemory: TimeInterval = 600

        static var `default`: Limits {
            #if os(tvOS)
                Limits(memoryBytes: 16_000_000)
            #elseif os(macOS)
                Limits(memoryBytes: 64_000_000)
            #else
                Limits(memoryBytes: 24_000_000)
            #endif
        }
    }

    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) {
            self.image = image
        }
    }

    /// Only touched on the actor; `Sendable` so its task can be awaited from a cancellation handler.
    private final class Flight: @unchecked Sendable {
        let task: Task<CGImage?, Never>
        var waiters = 0
        init(task: Task<CGImage?, Never>) {
            self.task = task
        }
    }

    private let fetch: Fetch
    private let disk: DiskImageCache
    private let limits: Limits
    private let memory = NSCache<NSString, Entry>()
    private var flights: [String: Flight] = [:]
    private var failures: [String: Date] = [:]
    private var activeDownloads = 0
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []

    init(disk: DiskImageCache, limits: Limits = .default, fetch: @escaping Fetch) {
        self.disk = disk
        self.limits = limits
        self.fetch = fetch
        memory.totalCostLimit = limits.memoryBytes
    }

    /// The image no larger than `maxPixel` on its longest side, or nil if it cannot be had.
    func image(for url: URL, maxPixel: Int) async -> CGImage? {
        let diskKey = DiskImageCache.key(for: url)
        let memoryKey = "\(diskKey)@\(maxPixel)"
        if let hit = memory.object(forKey: memoryKey as NSString) {
            return hit.image
        }
        if let failedAt = failures[diskKey] {
            if Date().timeIntervalSince(failedAt) < limits.failureMemory {
                return nil
            }
            failures[diskKey] = nil
        }

        let flight: Flight
        if let existing = flights[memoryKey] {
            flight = existing
        } else {
            let task = Task { await self.load(url, diskKey: diskKey, memoryKey: memoryKey, maxPixel: maxPixel) }
            flight = Flight(task: task)
            flights[memoryKey] = flight
        }
        flight.waiters += 1
        return await withTaskCancellationHandler {
            await flight.task.value
        } onCancel: {
            Task { await self.leave(memoryKey, flight) }
        }
    }

    /// Empties the memory cache. The disk cache is untouched, so the images come back
    /// without a download.
    func purgeMemory() {
        memory.removeAllObjects()
    }

    /// Asks for an image to be fetched ahead of need, with nobody waiting for it.
    func prefetch(_ url: URL, maxPixel: Int) {
        Task { _ = await self.image(for: url, maxPixel: maxPixel) }
    }

    // MARK: - Loading

    private func load(_ url: URL, diskKey: String, memoryKey: String, maxPixel: Int) async -> CGImage? {
        defer { flights[memoryKey] = nil }

        var data = await disk.data(forKey: diskKey)
        if data == nil {
            await acquireSlot()
            defer { releaseSlot() }
            guard !Task.isCancelled else { return nil }
            do {
                let fetched = try await fetch(url)
                guard fetched.count <= limits.maxImageBytes, ImageDownsampler.isImage(fetched) else {
                    failures[diskKey] = Date()
                    return nil
                }
                await disk.store(fetched, forKey: diskKey)
                data = fetched
            } catch {
                // A cancelled download is nobody's failure; do not remember it as one.
                if !(error is CancellationError), !Task.isCancelled {
                    failures[diskKey] = Date()
                }
                return nil
            }
        }
        guard let data else { return nil }

        guard let image = await Self.decode(data, maxPixel: maxPixel) else {
            // Bytes on disk that are not an image: drop them, so they are not tried again.
            await disk.remove(key: diskKey)
            failures[diskKey] = Date()
            return nil
        }
        memory.setObject(Entry(image), forKey: memoryKey as NSString, cost: ImageDownsampler.cost(of: image))
        return image
    }

    /// Off the actor on purpose: decoding is the expensive part, and the actor must stay
    /// free to answer the next row's cache hit.
    nonisolated static func decode(_ data: Data, maxPixel: Int) async -> CGImage? {
        ImageDownsampler.decode(data, maxPixel: maxPixel)
    }

    private func leave(_ key: String, _ flight: Flight) {
        flight.waiters -= 1
        if flight.waiters <= 0, flights[key] === flight {
            flight.task.cancel()
            flights[key] = nil
        }
    }

    // MARK: - Download slots

    private func acquireSlot() async {
        if activeDownloads < limits.maxConcurrentDownloads {
            activeDownloads += 1
            return
        }
        await withCheckedContinuation { slotWaiters.append($0) }
    }

    /// Hands the slot to the most recent waiter: that is the row on screen now.
    private func releaseSlot() {
        if let next = slotWaiters.popLast() {
            next.resume()
        } else {
            activeDownloads -= 1
        }
    }
}

// MARK: - The app's pipeline

extension ImagePipeline {
    static let shared: ImagePipeline = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = caches.appendingPathComponent("Panop/Images", isDirectory: true)
        let pipeline = ImagePipeline(
            disk: DiskImageCache(directory: directory, maxBytes: 120_000_000),
            fetch: ImagePipeline.networkFetch()
        )
        pipeline.releaseMemoryWhenAsked()
        return pipeline
    }()

    nonisolated static func networkFetch() -> Fetch {
        let configuration = URLSessionConfiguration.ephemeral
        // The disk cache is ours; a second one in URLSession would only double the storage.
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        return { url in
            var request = URLRequest(url: url)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    /// Frees decoded images on a memory warning and when the app leaves the screen.
    nonisolated func releaseMemoryWhenAsked() {
        #if canImport(UIKit)
            for name in [
                UIApplication.didReceiveMemoryWarningNotification,
                UIApplication.didEnterBackgroundNotification
            ] {
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [self] _ in
                    Task { await purgeMemory() }
                }
            }
        #endif
    }
}
