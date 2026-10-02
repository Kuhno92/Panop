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
        .library(name: "PanopEPG", targets: ["PanopEPG"]),
        .library(name: "PanopCatalog", targets: ["PanopCatalog"]),
        .library(name: "PanopPlayback", targets: ["PanopPlayback"]),
        .library(name: "PanopDiscover", targets: ["PanopDiscover"]),
        .library(name: "PanopSimkl", targets: ["PanopSimkl"])
    ],
    targets: [
        .target(name: "PanopCore"),
        .target(name: "PanopPlaylist", dependencies: ["PanopCore"]),
        .target(name: "PanopXtream", dependencies: ["PanopCore"]),
        .target(name: "PanopEPG", dependencies: ["PanopCore"]),
        .target(
            name: "PanopCatalog",
            dependencies: ["PanopCore", "PanopPlaylist", "PanopXtream", "PanopEPG"]
        ),
        .target(name: "PanopPlayback", dependencies: ["PanopCore"]),
        .target(name: "PanopDiscover", dependencies: ["PanopCore"]),
        // Kept apart so a licence decision about Simkl can drop it without touching the rest.
        .target(name: "PanopSimkl", dependencies: ["PanopCore", "PanopDiscover"]),

        .testTarget(name: "PanopCoreTests", dependencies: ["PanopCore"]),
        .testTarget(name: "PanopPlaylistTests", dependencies: ["PanopPlaylist"]),
        .testTarget(name: "PanopXtreamTests", dependencies: ["PanopXtream", "PanopCore"]),
        .testTarget(name: "PanopEPGTests", dependencies: ["PanopEPG", "PanopCore"]),
        .testTarget(
            name: "PanopCatalogTests",
            dependencies: ["PanopCatalog", "PanopCore", "PanopXtream", "PanopEPG", "PanopPlaylist"]
        ),
        .testTarget(name: "PanopPlaybackTests", dependencies: ["PanopPlayback"]),
        .testTarget(name: "PanopDiscoverTests", dependencies: ["PanopDiscover", "PanopCore"]),
        .testTarget(name: "PanopSimklTests", dependencies: ["PanopSimkl", "PanopDiscover", "PanopCore"])
    ],
    swiftLanguageModes: [.v6]
)
