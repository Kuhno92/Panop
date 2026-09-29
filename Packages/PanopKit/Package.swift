// swift-tools-version: 6.0
import PackageDescription

/// PanopKit is Panop's portable core: parsing, provider APIs, catalog
/// orchestration, and the playback abstraction.
///
/// Nothing here may import an Apple-only framework. The package must keep
/// compiling on Linux, Windows and Android so the same logic can later back a
/// non-Apple UI. See docs/adr/0007-portable-core.md. A SwiftLint custom rule and
/// a Linux CI job enforce it.
///
/// The `platforms:` list below constrains Apple platforms only; other platforms
/// are supported implicitly.
let package = Package(
    name: "PanopKit",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PanopCore", targets: ["PanopCore"]),
        .library(name: "PanopPlaylist", targets: ["PanopPlaylist"]),
        .library(name: "PanopXtream", targets: ["PanopXtream"]),
        .library(name: "PanopPlayback", targets: ["PanopPlayback"])
    ],
    targets: [
        .target(name: "PanopCore"),
        .target(name: "PanopPlaylist", dependencies: ["PanopCore"]),
        .target(name: "PanopXtream", dependencies: ["PanopCore"]),
        .target(name: "PanopPlayback", dependencies: ["PanopCore"]),

        .testTarget(name: "PanopCoreTests", dependencies: ["PanopCore"]),
        .testTarget(name: "PanopPlaylistTests", dependencies: ["PanopPlaylist"]),
        .testTarget(name: "PanopXtreamTests", dependencies: ["PanopXtream", "PanopCore"]),
        .testTarget(name: "PanopPlaybackTests", dependencies: ["PanopPlayback"])
    ],
    swiftLanguageModes: [.v6]
)
