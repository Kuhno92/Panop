import CoreGraphics
import SwiftUI

/// The colour a picture is mostly made of, for a glow that takes its tint from the title on show.
///
/// The picture is drawn into one pixel, which averages it. Cheap enough to do as it arrives (a handful of operations
/// on an image that is already decoded), and the result is lifted to a colour that shows as light on a dark page: an
/// average of a dark poster is near black, which would be no glow at all.
enum AmbientColor {
    static func of(_ image: CGImage) -> Color? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return lifted(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    /// The same hue, with enough saturation and brightness to glow.
    static func lifted(red: Double, green: Double, blue: Double) -> Color {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        var hue = 0.0
        if delta > 0.0001 {
            switch high {
            case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            case green: hue = (blue - red) / delta + 2
            default: hue = (red - green) / delta + 4
            }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 {
                hue += 1
            }
        }
        let saturation = high == 0 ? 0 : delta / high
        return Color(hue: hue, saturation: max(saturation, 0.55), brightness: max(high, 0.85))
    }
}
