// swift-tools-version: 6.0

import PackageDescription

/// A stand-in for the `LibDovi` package AetherEngine depends on (see Sources/Dovi/include/dovi.h for why).
/// Named like it so that, as a local package in the project, it takes its place in the dependency graph.
let package = Package(
    name: "LibDovi",
    platforms: [.iOS(.v16), .tvOS(.v17), .macOS(.v14), .visionOS(.v1)],
    products: [
        .library(name: "Dovi", targets: ["Dovi"])
    ],
    targets: [
        .target(name: "Dovi", path: "Sources/Dovi")
    ]
)
