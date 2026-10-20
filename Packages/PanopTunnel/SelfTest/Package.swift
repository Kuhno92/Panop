// swift-tools-version: 6.0
import PackageDescription

/// Runs the Go tunnel's end-to-end self-test on a simulator or the Mac. Uses its own build of the framework
/// (Scripts/build-tunnel.sh --selftest), which carries the stand-in server the shipped framework leaves out.
let package = Package(
    name: "PanopTunnelSelfTest",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    targets: [
        .binaryTarget(name: "PanopTunnel", path: "../build-selftest/PanopTunnel.xcframework"),
        .testTarget(name: "PanopTunnelTests", dependencies: ["PanopTunnel"])
    ]
)
