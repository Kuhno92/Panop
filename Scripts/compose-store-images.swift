// Frames App Store screenshots as marketing images: the screenshot on a gradient in Panop's colours, with a headline
// above.
// The output has the same size as the screenshot, which is a size App Store Connect accepts.
//
//   swift Scripts/compose-store-images.swift build/store/iphone build/store/iphone-marketing

import AppKit

func say(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

let captions: [String: String] = [
    "01-home": "All you watch, in one place",
    "02-live": "Live TV that starts fast",
    "03-guide": "A full TV guide, at a glance",
    "04-movies": "Movies and series, beautifully browsed",
    "05-series": "Pick up where you left off",
    "06-movie-grid": "Posters, ratings and progress"
]

guard CommandLine.arguments.count == 3 else {
    say("usage: compose-store-images <input folder> <output folder>")
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func pixels(_ image: NSImage) -> NSSize {
    guard let rep = image.representations.first else { return image.size }
    return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

for file in try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
    .filter({ $0.pathExtension == "png" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
{
    let name = file.deletingPathExtension().lastPathComponent
    guard let shot = NSImage(contentsOf: file), let caption = captions[name] else { continue }
    let size = pixels(shot)
    let width = Int(size.width), height = Int(size.height)
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let canvas = NSRect(origin: .zero, size: size)
    let portrait = size.height > size.width

    // Background: Panop's dark indigo to teal, with a soft glow behind the picture.
    NSGradient(colors: [
        NSColor(red: 0.07, green: 0.07, blue: 0.22, alpha: 1),
        NSColor(red: 0.02, green: 0.20, blue: 0.27, alpha: 1)
    ])?.draw(in: canvas, angle: -60)
    NSGradient(colors: [NSColor(red: 0.45, green: 0.35, blue: 1, alpha: 0.35), .clear])?
        .draw(
            fromCenter: NSPoint(x: size.width * 0.5, y: size.height * 0.45),
            radius: 0,
            toCenter: NSPoint(x: size.width * 0.5, y: size.height * 0.45),
            radius: size.width * 0.7,
            options: []
        )

    // Headline.
    let fontSize = portrait ? size.height * 0.032 : size.height * 0.062
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: NSColor.white,
        .paragraphStyle: style
    ]
    let headlineHeight = fontSize * 2.6
    let top = size.height * (portrait ? 0.045 : 0.05)
    let headline = NSRect(
        x: size.width * 0.06,
        y: size.height - top - headlineHeight,
        width: size.width * 0.88,
        height: headlineHeight
    )
    NSAttributedString(string: caption, attributes: attributes).draw(in: headline)

    // The screenshot, scaled to what is left, with rounded corners and a shadow.
    let bottom = size.height * 0.04
    let available = NSSize(
        width: size.width * (portrait ? 0.86 : 0.84),
        height: headline.minY - bottom - size.height * 0.015
    )
    let scale = min(available.width / size.width, available.height / size.height)
    let target = NSSize(width: size.width * scale, height: size.height * scale)
    let frame = NSRect(x: (size.width - target.width) / 2, y: bottom, width: target.width, height: target.height)
    let radius = portrait ? target.width * 0.07 : target.width * 0.02
    let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = size.width * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size.width * 0.012)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    shot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.18).setStroke()
    path.lineWidth = max(2, size.width * 0.002)
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { continue }
    try data.write(to: output.appendingPathComponent(name + ".png"))
    say("\(output.lastPathComponent)/\(name).png  \(width)x\(height)")
}
