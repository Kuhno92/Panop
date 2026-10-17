import CoreGraphics
import Foundation
import SVGView
import SwiftUI

/// Draws a vector logo to a bitmap, so it goes through the image pipeline like any other picture.
///
/// ImageIO cannot read SVG, and sportapi.ai keeps many club crests (the Bundesliga's among them) as SVG files. SVGView
/// reads the file and SwiftUI draws it, which is also why this runs on the main actor: `ImageRenderer` has to. A crest
/// is a few kilobytes of paths, and the result is cached by the pipeline at the size it was asked for, so it is drawn
/// once per size.
enum SVGRaster {
    /// Whether `data` is SVG text: an `<svg` element near its start (after an XML declaration, a comment or a doctype).
    nonisolated static func isSVG(_ data: Data) -> Bool {
        let head = data.prefix(2048)
        guard let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) else {
            return false
        }
        return text.contains("<svg")
    }

    /// The picture inside a square of `maxPixel` points on a side, at its own proportions and centred, on a clear
    /// ground. Nil when the file is not a drawing SVGView understands.
    @MainActor
    static func render(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let node = SVGParser.parse(data: data) else { return nil }
        let side = CGFloat(min(max(maxPixel, 16), 512))
        let renderer = ImageRenderer(content: SVGView(svg: node).frame(width: side, height: side))
        renderer.scale = 1
        return renderer.cgImage
    }
}
