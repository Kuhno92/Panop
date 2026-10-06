// swift-tools-version: 6.0

import PackageDescription

/// KSPlayer (GPL-3.0) and its FFmpeg 6, behind an interface with no KSPlayer or FFmpeg type in it.
///
/// `-enable-library-evolution` is what keeps FFmpegKit's C modules out of the app's compile: without it, the app
/// sees two definitions of FFmpeg's types (these and AetherEngine's, LumeEngine's) and Clang refuses with
/// "'AV_PIX_FMT_OHCODEC' from module 'AetherLibavutil' is not present in definition of 'enum AVPixelFormat' in
/// module 'Libavutil'". It can only be an unsafe flag, which SwiftPM allows for a local package like this one,
/// so this must stay a path dependency (see docs/engines.md).
let package = Package(
    name: "KSPlayerBridge",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KSPlayerBridge", type: .dynamic, targets: ["KSPlayerBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/kingslay/KSPlayer", exact: "2.3.4")
    ],
    targets: [
        .target(
            name: "KSPlayerBridge",
            dependencies: [.product(name: "KSPlayer", package: "KSPlayer")],
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"]),
                // A plain `import` is internal: KSPlayer, and the FFmpeg modules behind it, stay out of what
                // the app sees of this package.
                .enableUpcomingFeature("InternalImportsByDefault")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
