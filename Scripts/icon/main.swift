// Draws Panop's icon with CoreGraphics and writes it as PNGs, so the icon is code rather than a binary
// nobody can edit. Run through Scripts/make-app-icon.sh, which builds and places every size.
//
// The idea: Argus Panoptes, the giant with a hundred eyes who sees everything, as one eye. The pupil is
// a play triangle, which is what says "streaming". Nothing else is drawn.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Layer { case background, eye, full }

let size = 1024.0
let space = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255, alpha: alpha
    )
}

/// Two looks for the same idea. `classic` is the plain outline; `modern` has depth, colour and light.
/// Chosen with PANOP_ICON_STYLE, and `modern` unless told otherwise.
let useClassic = ProcessInfo.processInfo.environment["PANOP_ICON_STYLE"] == "classic"

/// The canvas is always 1024 points square; sizes are scaled when written.
func draw(_ layer: Layer, in ctx: CGContext) {
    if layer == .background || layer == .full {
        if useClassic {
            drawBackground(in: ctx)
        } else {
            drawModernBackground(in: ctx)
        }
    }
    if layer == .eye || layer == .full {
        if useClassic {
            drawEye(in: ctx)
        } else {
            drawModernEye(in: ctx)
        }
    }
}

func drawBackground(in ctx: CGContext) {
    do {
        // Deep night blue, lighter toward the middle so the eye sits in a glow. The end colour carries on
        // past the radius, so a wide canvas is covered to its edges.
        let base = CGGradient(
            colorsSpace: space,
            colors: [color(0x1B2A6B), color(0x070B24)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawRadialGradient(
            base, startCenter: CGPoint(x: size / 2, y: size * 0.56), startRadius: 0,
            endCenter: CGPoint(x: size / 2, y: size * 0.56), endRadius: size * 0.78, options: .drawsAfterEndLocation
        )
    }
}

func drawEye(in ctx: CGContext) {
    let centre = CGPoint(x: size / 2, y: size / 2)

    // The eye: an almond, two arcs meeting in points.
    let halfWidth = 380.0
    let halfHeight = 212.0
    let almond = CGMutablePath()
    almond.move(to: CGPoint(x: centre.x - halfWidth, y: centre.y))
    almond.addCurve(
        to: CGPoint(x: centre.x + halfWidth, y: centre.y),
        control1: CGPoint(x: centre.x - halfWidth * 0.45, y: centre.y + halfHeight * 1.38),
        control2: CGPoint(x: centre.x + halfWidth * 0.45, y: centre.y + halfHeight * 1.38)
    )
    almond.addCurve(
        to: CGPoint(x: centre.x - halfWidth, y: centre.y),
        control1: CGPoint(x: centre.x + halfWidth * 0.45, y: centre.y - halfHeight * 1.38),
        control2: CGPoint(x: centre.x - halfWidth * 0.45, y: centre.y - halfHeight * 1.38)
    )
    almond.closeSubpath()

    // A soft fill so the eye reads as an eye and not as an outline.
    ctx.saveGState()
    ctx.addPath(almond)
    ctx.clip()
    let fill = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFFFFF, 0.20), color(0xFFFFFF, 0.05)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        fill, start: CGPoint(x: size / 2, y: centre.y + halfHeight), end: CGPoint(
            x: size / 2,
            y: centre.y - halfHeight
        ),
        options: []
    )
    ctx.restoreGState()

    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(44)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(almond)
    ctx.strokePath()

    // A ring of small dots around the iris: the hundred eyes, and also a lens.
    let dots = 20
    let ringRadius = 182.0
    ctx.setFillColor(color(0xFFFFFF, 0.55))
    for index in 0 ..< dots {
        let angle = Double(index) / Double(dots) * 2 * .pi
        let dot = CGPoint(x: centre.x + ringRadius * cos(angle), y: centre.y + ringRadius * sin(angle))
        ctx.fillEllipse(in: CGRect(x: dot.x - 7, y: dot.y - 7, width: 14, height: 14))
    }

    // The iris, in the cool colour of a signal.
    let irisRadius = 150.0
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(
        x: centre.x - irisRadius,
        y: centre.y - irisRadius,
        width: irisRadius * 2,
        height: irisRadius * 2
    ))
    ctx.clip()
    let iris = CGGradient(colorsSpace: space, colors: [color(0x5CE1FF), color(0x2A7BFF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        iris, start: CGPoint(x: centre.x - irisRadius, y: centre.y + irisRadius),
        end: CGPoint(x: centre.x + irisRadius, y: centre.y - irisRadius), options: []
    )
    ctx.restoreGState()

    // The pupil is a play triangle, nudged right so it looks centred (a triangle's middle is not its weight).
    let triangle = CGMutablePath()
    let edge = 118.0
    let tipX = centre.x + edge * 0.62
    let backX = centre.x - edge * 0.52
    triangle.move(to: CGPoint(x: backX, y: centre.y + edge * 0.62))
    triangle.addLine(to: CGPoint(x: tipX, y: centre.y))
    triangle.addLine(to: CGPoint(x: backX, y: centre.y - edge * 0.62))
    triangle.closeSubpath()
    ctx.setFillColor(color(0xFFFFFF))
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(26)
    ctx.addPath(triangle)
    ctx.drawPath(using: .fillStroke)
}

/// What is made: the same drawing in each platform's shape.
enum Variant: String {
    /// Full square, no transparency: the system rounds it.
    case ios
    /// A rounded body inside a margin, with a shadow: macOS does not round for you.
    case mac
    /// The two layers of an Apple TV icon, which moves them apart as it is focused.
    case tvBack, tvFront
    /// The picture above the Apple TV home screen.
    case shelf
}

func render(_ variant: Variant, width: Int, height: Int, to path: String) {
    // No alpha channel where the picture fills its canvas: the App Store refuses an icon that has one,
    // and a flat picture is far smaller as a JPEG than as a PNG.
    let opaque = variant == .ios || variant == .tvBack || variant == .shelf
    let isJPEG = path.hasSuffix(".jpg")
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info
    ) else { fatalError("no drawing context for \(width)x\(height)") }
    ctx.setShouldAntialias(true)
    let canvasWidth = CGFloat(width)
    let canvasHeight = CGFloat(height)

    /// Runs `body` with the 1024 square scaled by `factor` of the canvas height and centred.
    func centred(_ factor: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        let scale = canvasHeight * factor / 1024
        ctx.translateBy(x: canvasWidth / 2 - 512 * scale, y: canvasHeight / 2 - 512 * scale)
        ctx.scaleBy(x: scale, y: scale)
        body()
        ctx.restoreGState()
    }

    switch variant {
    case .ios:
        centred(1) { draw(.full, in: ctx) }
    case .mac:
        // Apple's template: a 824 point body in a 1024 canvas, corners about a fifth of it.
        let body = CGRect(
            x: canvasWidth * 100 / 1024, y: canvasHeight * 100 / 1024,
            width: canvasWidth * 824 / 1024, height: canvasHeight * 824 / 1024
        )
        let shape = CGPath(
            roundedRect: body,
            cornerWidth: body.width * 0.2237,
            cornerHeight: body.width * 0.2237,
            transform: nil
        )
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -canvasWidth * 12 / 1024),
            blur: canvasWidth * 28 / 1024,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        ctx.addPath(shape)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.translateBy(x: body.minX, y: body.minY)
        ctx.scaleBy(x: body.width / 1024, y: body.height / 1024)
        draw(.full, in: ctx)
        ctx.restoreGState()
    case .tvBack:
        centred(1) { draw(.background, in: ctx) }
    case .tvFront:
        centred(0.92) { draw(.eye, in: ctx) }
    case .shelf:
        centred(1) { draw(.background, in: ctx) }
        centred(0.8) { draw(.eye, in: ctx) }
    }
    let url = URL(fileURLWithPath: path) as CFURL
    let type = (isJPEG ? UTType.jpeg : UTType.png).identifier as CFString
    guard let image = ctx.makeImage(), let destination = CGImageDestinationCreateWithURL(url, type, 1, nil) else {
        fatalError("cannot write \(path)")
    }
    CGImageDestinationAddImage(
        destination,
        image,
        isJPEG ? [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary : nil
    )
    CGImageDestinationFinalize(destination)
}

// usage: make-icon <variant> <width> <height> <output.png>
let arguments = CommandLine.arguments
guard arguments.count == 5, let variant = Variant(rawValue: arguments[1]),
      let width = Int(arguments[2]), let height = Int(arguments[3])
else {
    FileHandle.standardError
        .write(Data("usage: make-icon ios|mac|tvBack|tvFront|shelf <width> <height> <out.png>\n".utf8))
    exit(2)
}

render(variant, width: width, height: height, to: arguments[4])
