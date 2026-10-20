// swift-tools-version: 6.0
import PackageDescription

/// The Go tunnel, built by Scripts/build-tunnel.sh into build/PanopTunnel.xcframework (not committed: it is
/// generated, and large; Scripts/ensure-tunnel.sh builds it when it is missing or stale). A local path package,
/// like LumeEngine, so nothing is downloaded at resolve time.
let package = Package(
    name: "PanopTunnel",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PanopTunnelKit", targets: ["PanopTunnelKit"])
    ],
    targets: [
        .binaryTarget(name: "PanopTunnel", path: "build/PanopTunnel.xcframework"),
        .target(name: "PanopTunnelKit", dependencies: ["PanopTunnel"])
    ]
)
