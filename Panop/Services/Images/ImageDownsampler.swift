import CoreGraphics
import Foundation
import ImageIO

/// Decodes an image straight to the size it will be drawn at.
///
/// A channel logo is often a few thousand pixels square and shown at 44 points. Decoding it
/// whole costs tens of megabytes for a thumbnail, and a list of a few hundred rows is how an
/// Apple TV gets killed. ImageIO decodes to the target size directly, and does it here, on
/// the calling thread, so nothing is left to decode lazily on the main thread at draw time.
nonisolated enum ImageDownsampler {
    /// The image no larger than `maxPixel` on its longest side, or nil if `data` is not an
    /// image. Never upscales.
    static func decode(_ data: Data, maxPixel: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// Whether `data` begins like an image, without decoding it.
    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// Bytes a decoded image occupies, for the memory cache's budget.
    static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}
