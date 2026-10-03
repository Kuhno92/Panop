// The modern look: colour that shifts from violet to blue, rings that spread out like a broadcast (and
// like the eyes of a peacock's tail, which is what Argus's eyes became), a glassy eye, a glowing iris.

import CoreGraphics
import Foundation

private let canvas = 1024.0
private let middle = CGPoint(x: canvas / 2, y: canvas / 2)

private struct IrisStop {
    var red: Double
    var green: Double
    var blue: Double
}

func drawModernBackground(in ctx: CGContext) {
    // Violet at the top left to deep blue at the bottom right.
    let base = CGGradient(
        colorsSpace: space, colors: [color(0x3A1F8F), color(0x14307F), color(0x061230)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        base,
        start: CGPoint(x: 0, y: canvas),
        end: CGPoint(x: canvas, y: 0),
        options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
    )
    // A glow behind the eye.
    let glow = CGGradient(
        colorsSpace: space,
        colors: [color(0x6E8BFF, 0.55), color(0x6E8BFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: middle,
        startRadius: 0,
        endCenter: middle,
        endRadius: canvas * 0.62,
        options: []
    )
}

func drawModernEye(in ctx: CGContext) {
    drawRings(in: ctx)
    let almond = almondPath()
    drawGlass(almond, in: ctx)
    drawIris(in: ctx)
    drawPupil(in: ctx)
}

/// Rings spreading from the iris, fainter as they go: a signal, and the eyes of a feather.
private func drawRings(in ctx: CGContext) {
    ctx.saveGState()
    for (index, radius) in [292.0, 372.0, 452.0, 532.0].enumerated() {
        let alpha = 0.34 - Double(index) * 0.075
        ctx.setStrokeColor(color(0x9FD8FF, alpha))
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: CGRect(x: middle.x - radius, y: middle.y - radius, width: radius * 2, height: radius * 2))
    }
    ctx.restoreGState()
}

private func almondPath() -> CGPath {
    let halfWidth = 388.0
    let halfHeight = 218.0
    let path = CGMutablePath()
    path.move(to: CGPoint(x: middle.x - halfWidth, y: middle.y))
    path.addCurve(
        to: CGPoint(x: middle.x + halfWidth, y: middle.y),
        control1: CGPoint(x: middle.x - halfWidth * 0.45, y: middle.y + halfHeight * 1.38),
        control2: CGPoint(x: middle.x + halfWidth * 0.45, y: middle.y + halfHeight * 1.38)
    )
    path.addCurve(
        to: CGPoint(x: middle.x - halfWidth, y: middle.y),
        control1: CGPoint(x: middle.x + halfWidth * 0.45, y: middle.y - halfHeight * 1.38),
        control2: CGPoint(x: middle.x - halfWidth * 0.45, y: middle.y - halfHeight * 1.38)
    )
    path.closeSubpath()
    return path
}

/// The eye as glass: a dark tinted body, a bright rim, and a sheen across the top.
private func drawGlass(_ almond: CGPath, in ctx: CGContext) {
    ctx.saveGState()
    ctx.addPath(almond)
    ctx.clip()
    let body = CGGradient(
        colorsSpace: space,
        colors: [color(0x1B2D7A, 0.92), color(0x07102E, 0.96)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        body,
        start: CGPoint(x: middle.x, y: middle.y + 230),
        end: CGPoint(x: middle.x, y: middle.y - 230),
        options: []
    )
    // The sheen: a lighter band over the upper lid.
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFFFFF, 0.30), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: middle.x, y: middle.y + 230),
        end: CGPoint(x: middle.x, y: middle.y + 20),
        options: []
    )
    ctx.restoreGState()

    // The rim, with a light of its own.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: color(0x6FD6FF, 0.75))
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(40)
    ctx.setLineJoin(.round)
    ctx.addPath(almond)
    ctx.strokePath()
    ctx.restoreGState()
}

/// A ring of colour that turns from cyan through blue to violet and back, and a ring of small eyes.
private func drawIris(in ctx: CGContext) {
    let outer = 168.0
    let segments = 240
    let stops = [
        IrisStop(red: 0.20, green: 0.88, blue: 1.00), IrisStop(red: 0.23, green: 0.48, blue: 1.00),
        IrisStop(red: 0.62, green: 0.36, blue: 1.00), IrisStop(red: 0.23, green: 0.48, blue: 1.00),
        IrisStop(red: 0.20, green: 0.88, blue: 1.00)
    ]
    for index in 0 ..< segments {
        let fraction = Double(index) / Double(segments)
        let position = fraction * Double(stops.count - 1)
        let lower = Int(position)
        let blend = position - Double(lower)
        let from = stops[lower]
        let to = stops[min(lower + 1, stops.count - 1)]
        ctx.setFillColor(CGColor(
            red: from.red + (to.red - from.red) * blend, green: from.green + (to.green - from.green) * blend,
            blue: from.blue + (to.blue - from.blue) * blend, alpha: 1
        ))
        let start = fraction * 2 * .pi
        let end = (fraction + 1.2 / Double(segments)) * 2 * .pi
        ctx.move(to: middle)
        ctx.addArc(center: middle, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        ctx.closePath()
        ctx.fillPath()
    }
    // Depth: darker toward the edge and toward the middle, so it looks like a lens and not a disc.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: middle.x - outer, y: middle.y - outer, width: outer * 2, height: outer * 2))
    ctx.clip()
    let depth = CGGradient(
        colorsSpace: space, colors: [color(0x000020, 0.55), color(0x000020, 0), color(0x000020, 0.50)] as CFArray,
        locations: [0, 0.5, 1]
    )!
    ctx.drawRadialGradient(
        depth,
        startCenter: middle,
        startRadius: 40,
        endCenter: middle,
        endRadius: outer,
        options: []
    )
    ctx.restoreGState()
    ctx.setStrokeColor(color(0xFFFFFF, 0.85))
    ctx.setLineWidth(6)
    ctx.strokeEllipse(in: CGRect(x: middle.x - outer, y: middle.y - outer, width: outer * 2, height: outer * 2))

    // The hundred eyes, as a ring of dots outside the iris.
    ctx.setFillColor(color(0xFFFFFF, 0.6))
    let dots = 28
    for index in 0 ..< dots {
        let angle = Double(index) / Double(dots) * 2 * .pi
        let point = CGPoint(x: middle.x + 192 * cos(angle), y: middle.y + 192 * sin(angle))
        ctx.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
    }
}

/// A dark pupil with the play triangle lit inside it, and a highlight on the iris.
private func drawPupil(in ctx: CGContext) {
    let radius = 104.0
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0x000020, 0.7))
    ctx.setFillColor(color(0x0A1038))
    ctx.fillEllipse(in: CGRect(x: middle.x - radius, y: middle.y - radius, width: radius * 2, height: radius * 2))
    ctx.restoreGState()

    let edge = 92.0
    let triangle = CGMutablePath()
    let tip = CGPoint(x: middle.x + edge * 0.66, y: middle.y)
    let backX = middle.x - edge * 0.50
    triangle.move(to: CGPoint(x: backX, y: middle.y + edge * 0.62))
    triangle.addLine(to: tip)
    triangle.addLine(to: CGPoint(x: backX, y: middle.y - edge * 0.62))
    triangle.closeSubpath()
    // The glow first, and the crisp white triangle over it, so the glow never tints the white.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0x6FD6FF, 1))
    ctx.setFillColor(color(0x6FD6FF))
    ctx.setStrokeColor(color(0x6FD6FF))
    ctx.setLineWidth(22)
    ctx.setLineJoin(.round)
    ctx.addPath(triangle)
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()
    ctx.setFillColor(color(0xFFFFFF))
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(22)
    ctx.setLineJoin(.round)
    ctx.addPath(triangle)
    ctx.drawPath(using: .fillStroke)

    // A window's reflection, up and to the left.
    ctx.saveGState()
    ctx.translateBy(x: middle.x - 72, y: middle.y + 96)
    ctx.rotate(by: .pi / 5)
    ctx.setFillColor(color(0xFFFFFF, 0.55))
    ctx.fillEllipse(in: CGRect(x: -34, y: -14, width: 68, height: 28))
    ctx.restoreGState()
}
