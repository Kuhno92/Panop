#if os(macOS)
    import CoreGraphics
    import Foundation
    import ImageIO
    @testable import Panop
    import SwiftUI
    import Testing
    import UniformTypeIdentifiers

    /// Renders channel rows with logos to /tmp/panop-logos.png. Not an assertion about
    /// pixels. Off unless `PANOP_SNAPSHOT=1`, like the others.
    @Suite("Logo snapshot", .enabled(if: ProcessInfo.processInfo.environment["PANOP_SNAPSHOT"] == "1"))
    @MainActor
    struct LogoSnapshot {
        private func logo(width: Int, height: Int, color: CGColor, letter: String) throws -> Data {
            let context = try #require(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: width / 4, y: height / 3, width: width / 2, height: height / 3))
            let image = try #require(context.makeImage())
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil
            ))
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            return data as Data
        }

        @Test
        func `render`() async throws {
            let square = try logo(
                width: 1200,
                height: 1200,
                color: CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1),
                letter: "A"
            )
            let wide = try logo(
                width: 1600,
                height: 400,
                color: CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1),
                letter: "B"
            )
            let tall = try logo(
                width: 300,
                height: 900,
                color: CGColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1),
                letter: "C"
            )
            let pipeline = ImagePipeline(
                disk: DiskImageCache(
                    directory: FileManager.default.temporaryDirectory.appendingPathComponent("logo-snap-\(UUID())"),
                    maxBytes: 5_000_000
                ),
                limits: ImagePipeline.Limits(memoryBytes: 8_000_000)
            ) { url in
                switch url.lastPathComponent {
                case "square.png": return square
                case "wide.png": return wide
                case "tall.png": return tall
                default: throw URLError(.fileDoesNotExist)
                }
            }

            struct Row {
                let name: String
                let logo: String?
                let group: String
            }
            let rows = [
                Row(name: "Das Erste HD", logo: "http://l/square.png", group: "Germany"),
                Row(name: "ZDF Info (a wide logo)", logo: "http://l/wide.png", group: "Germany"),
                Row(name: "3sat (a tall logo)", logo: "http://l/tall.png", group: "Germany"),
                Row(name: "A logo that fails to load", logo: "http://l/missing.png", group: "News"),
                Row(name: "No logo at all", logo: nil, group: "Misc")
            ]
            let view = VStack(spacing: 0) {
                ForEach(rows, id: \.name) { row in
                    LabeledContent {
                        Text(row.group).foregroundStyle(.secondary)
                    } label: {
                        HStack(spacing: 12) {
                            ChannelLogo(address: row.logo)
                            Text(row.name)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    Divider()
                }
            }
            .environment(\.imagePipeline, pipeline)
            .frame(width: 520)
            .background(Color(nsColor: .windowBackgroundColor))

            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(1200))
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/panop-logos.png"))
            window.close()
        }
    }
#endif
