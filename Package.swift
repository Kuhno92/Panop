// swift-tools-version: 6.0
import PackageDescription

/// This manifest exists ONLY to vendor developer tooling. It builds nothing.
///
/// The app is built by Panop.xcodeproj, and the portable logic lives in
/// Packages/PanopKit. Keeping the linters here means a fresh clone needs only
/// Xcode's toolchain: no Homebrew, no Mint, no global installs, and every
/// contributor and CI runner gets byte-identical tool versions.
///
/// Run Scripts/setup.sh once after cloning.
let package = Package(
    name: "PanopTooling",
    dependencies: [
        .package(url: "https://github.com/csjones/lefthook-plugin.git", from: "1.10.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", from: "0.57.0"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat.git", from: "0.55.0")
    ],
    targets: []
)
