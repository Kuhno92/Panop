// swift-tools-version:5.9

import PackageDescription

// exyte/SVGView 1.0.6 (MIT, see LICENSE), copied as it is except for this manifest: upstream declares no tvOS, so
// SwiftPM gives it tvOS 9 and its use of `TapGesture` does not compile there. Reached only through the app target,
// which draws a club's SVG crest to a bitmap (`SVGRaster`).
let package = Package(
    name: "SVGView",
    platforms: [.macOS(.v11), .iOS(.v14), .tvOS(.v16), .watchOS(.v7)],
    products: [
        .library(name: "SVGView", targets: ["SVGView"])
    ],
    targets: [
        .target(name: "SVGView", path: "Source")
    ],
    swiftLanguageVersions: [.v5]
)
