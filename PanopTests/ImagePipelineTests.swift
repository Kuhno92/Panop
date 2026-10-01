import CoreGraphics
import Foundation
import ImageIO
@testable import Panop
import Testing
import UniformTypeIdentifiers

/// A real PNG of a given size, so decoding and downsampling are exercised for real.
private func png(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// What the pipeline asked the network for.
private actor FetchLog {
    private(set) var urls: [URL] = []
    private(set) var active = 0
    private(set) var peak = 0
    private(set) var cancelled = 0

    var count: Int {
        urls.count
    }

    func begin(_ url: URL) {
        urls.append(url)
        active += 1
        peak = max(peak, active)
    }

    func end() {
        active -= 1
    }

    func noteCancelled() {
        cancelled += 1
    }
}

private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("panop-images-\(UUID().uuidString)")
}

private func makePipeline(
    directory: URL = makeDirectory(),
    limits: ImagePipeline.Limits = ImagePipeline.Limits(memoryBytes: 8_000_000),
    diskBytes: Int = 10_000_000,
    fetch: @escaping ImagePipeline.Fetch
) -> ImagePipeline {
    ImagePipeline(disk: DiskImageCache(directory: directory, maxBytes: diskBytes), limits: limits, fetch: fetch)
}

private let logo = URL(string: "http://logos.example/a.png")!

@Suite("Image pipeline")
struct ImagePipelineTests {
    // MARK: - Decoding

    @Test
    func `a large image is decoded at the size asked for, never larger`() async throws {
        let big = try png(width: 2000, height: 1000)
        let pipeline = makePipeline { _ in big }

        let image = try #require(await pipeline.image(for: logo, maxPixel: 100))

        #expect(max(image.width, image.height) == 100, "longest side is the limit")
        #expect(image.width == 100 && image.height == 50, "and the shape is kept")
    }

    @Test
    func `a small image is not enlarged`() async throws {
        let small = try png(width: 20, height: 20)
        let pipeline = makePipeline { _ in small }

        let image = try #require(await pipeline.image(for: logo, maxPixel: 200))

        #expect(image.width <= 200)
    }

    // MARK: - Caching

    @Test
    func `asking again is answered from memory`() async throws {
        let data = try png(width: 50, height: 50)
        let log = FetchLog()
        let pipeline = makePipeline { url in
            await log.begin(url)
            await log.end()
            return data
        }

        _ = await pipeline.image(for: logo, maxPixel: 64)
        _ = await pipeline.image(for: logo, maxPixel: 64)
        _ = await pipeline.image(for: logo, maxPixel: 64)

        #expect(await log.count == 1)
    }

    @Test
    func `after memory is emptied the image comes back from disk, not the network`() async throws {
        let data = try png(width: 50, height: 50)
        let log = FetchLog()
        let pipeline = makePipeline { url in
            await log.begin(url)
            await log.end()
            return data
        }
        _ = await pipeline.image(for: logo, maxPixel: 64)

        await pipeline.purgeMemory()
        let again = await pipeline.image(for: logo, maxPixel: 64)

        #expect(again != nil)
        #expect(await log.count == 1, "memory was purged but the bytes were still on disk")
    }

    @Test
    func `a new launch finds the images the last one saved`() async throws {
        let data = try png(width: 50, height: 50)
        let directory = makeDirectory()
        let first = makePipeline(directory: directory) { _ in data }
        _ = await first.image(for: logo, maxPixel: 64)

        let log = FetchLog()
        let second = makePipeline(directory: directory) { url in
            await log.begin(url)
            await log.end()
            return data
        }
        let image = await second.image(for: logo, maxPixel: 64)

        #expect(image != nil)
        #expect(await log.urls.isEmpty)
    }

    @Test
    func `another size of the same image needs no second download`() async throws {
        let data = try png(width: 600, height: 600)
        let log = FetchLog()
        let pipeline = makePipeline { url in
            await log.begin(url)
            await log.end()
            return data
        }

        let small = await pipeline.image(for: logo, maxPixel: 64)
        let large = await pipeline.image(for: logo, maxPixel: 256)

        #expect(small?.width == 64)
        #expect(large?.width == 256)
        #expect(await log.count == 1)
    }

    // MARK: - Many rows asking at once

    @Test
    func `many rows asking for one logo cause one download`() async throws {
        let data = try png(width: 50, height: 50)
        let log = FetchLog()
        let pipeline = makePipeline { url in
            await log.begin(url)
            try await Task.sleep(for: .milliseconds(100))
            await log.end()
            return data
        }

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 25 {
                group.addTask { await pipeline.image(for: logo, maxPixel: 64) != nil }
            }
            for await ok in group {
                #expect(ok)
            }
        }

        #expect(await log.count == 1)
    }

    @Test
    func `downloads in flight are capped`() async throws {
        let data = try png(width: 20, height: 20)
        let log = FetchLog()
        var limits = ImagePipeline.Limits(memoryBytes: 8_000_000)
        limits.maxConcurrentDownloads = 3
        let pipeline = makePipeline(limits: limits) { url in
            await log.begin(url)
            try await Task.sleep(for: .milliseconds(60))
            await log.end()
            return data
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 20 {
                let url = URL(string: "http://logos.example/\(index).png")!
                group.addTask { _ = await pipeline.image(for: url, maxPixel: 64) }
            }
        }

        #expect(await log.count == 20)
        let peak = await log.peak
        #expect(peak <= 3, "peak was \(peak)")
    }

    // MARK: - Cancellation

    @Test
    func `a download nobody is waiting for any more is stopped`() async throws {
        let log = FetchLog()
        let pipeline = makePipeline { url in
            await log.begin(url)
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                await log.noteCancelled()
                throw error
            }
            return Data()
        }

        let waiter = Task { await pipeline.image(for: logo, maxPixel: 64) }
        try await Task.sleep(for: .milliseconds(100))
        waiter.cancel()
        _ = await waiter.value

        for _ in 0 ..< 100 where await log.cancelled == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await log.cancelled == 1, "the fetch kept running with nobody to use it")
    }

    @Test
    func `a download is kept while someone still wants it`() async throws {
        let data = try png(width: 30, height: 30)
        let pipeline = makePipeline { _ in
            try await Task.sleep(for: .milliseconds(200))
            return data
        }

        let leaving = Task { await pipeline.image(for: logo, maxPixel: 64) }
        let staying = Task { await pipeline.image(for: logo, maxPixel: 64) }
        try await Task.sleep(for: .milliseconds(50))
        leaving.cancel()

        #expect(await staying.value != nil, "one row scrolling away must not break another")
    }

    // MARK: - Failures

    @Test
    func `a failed logo is not asked for again straight away`() async {
        let log = FetchLog()
        let pipeline = makePipeline { url in
            await log.begin(url)
            await log.end()
            throw URLError(.cannotFindHost)
        }

        let first = await pipeline.image(for: logo, maxPixel: 64)
        let second = await pipeline.image(for: logo, maxPixel: 64)

        #expect(first == nil && second == nil)
        #expect(await log.count == 1)
    }

    @Test
    func `a failure is forgotten after a while`() async {
        let log = FetchLog()
        var limits = ImagePipeline.Limits(memoryBytes: 8_000_000)
        limits.failureMemory = 0.05
        let pipeline = makePipeline(limits: limits) { url in
            await log.begin(url)
            await log.end()
            throw URLError(.timedOut)
        }

        _ = await pipeline.image(for: logo, maxPixel: 64)
        try? await Task.sleep(for: .milliseconds(120))
        _ = await pipeline.image(for: logo, maxPixel: 64)

        #expect(await log.count == 2)
    }

    @Test
    func `bytes that are not an image are refused and not kept`() async throws {
        let directory = makeDirectory()
        let pipeline = makePipeline(directory: directory) { _ in Data("<html>not found</html>".utf8) }

        let image = await pipeline.image(for: logo, maxPixel: 64)

        #expect(image == nil)
        let stored = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(stored.isEmpty, "a web page was cached as if it were a logo")
    }

    @Test
    func `an image over the size limit is refused`() async throws {
        let big = try png(width: 800, height: 800)
        var limits = ImagePipeline.Limits(memoryBytes: 8_000_000)
        limits.maxImageBytes = big.count - 1
        let pipeline = makePipeline(limits: limits) { _ in big }

        #expect(await pipeline.image(for: logo, maxPixel: 64) == nil)
    }

    // MARK: - Disk size

    @Test
    func `the disk cache stays within its limit and drops the oldest first`() async throws {
        let directory = makeDirectory()
        let cache = DiskImageCache(directory: directory, maxBytes: 3500)
        let chunk = Data(repeating: 7, count: 1000)

        await cache.store(chunk, forKey: "oldest")
        try await Task.sleep(for: .milliseconds(20))
        await cache.store(chunk, forKey: "older")
        try await Task.sleep(for: .milliseconds(20))
        await cache.store(chunk, forKey: "newer")
        try await Task.sleep(for: .milliseconds(20))
        // Using "oldest" makes it the newest.
        #expect(await cache.data(forKey: "oldest") != nil)
        try await Task.sleep(for: .milliseconds(20))
        await cache.store(chunk, forKey: "newest")
        await cache.store(chunk, forKey: "latest")

        await cache.trim()

        #expect(await cache.totalBytes() <= 3500)
        #expect(await cache.data(forKey: "older") == nil, "the least recently used goes first")
        #expect(await cache.data(forKey: "latest") != nil)
    }

    @Test
    func `the same address always has the same key, and different ones differ`() throws {
        let one = try DiskImageCache.key(for: #require(URL(string: "http://a/b.png")))
        #expect(try one == DiskImageCache.key(for: #require(URL(string: "http://a/b.png"))))
        #expect(try one != DiskImageCache.key(for: #require(URL(string: "http://a/c.png"))))
        #expect(one.count == 64)
    }
}

@Suite("Channel logo")
struct ChannelLogoTests {
    @Test(arguments: [
        (30.0, 64), (44.0, 64), (64.0, 64), (88.0, 128), (132.0, 192), (200.0, 256), (3000.0, 512)
    ])
    func `sizes round up to a few steps so images are shared`(points: Double, expected: Int) {
        #expect(ChannelLogo.pixels(for: points) == expected)
    }
}
