# 0007. Keep PanopKit portable for Android, Windows and Linux

**Status:** accepted

## Context

Panop targets Apple platforms first, but Android, Windows, and Linux are intended later. The
conventional way to share logic across those is a Kotlin Multiplatform core, which means a
second toolchain, a second language, and Gradle sitting alongside Xcode.

That calculus changed in 2026:

- **Swift 6.3** (March 2026) shipped the first official Swift SDK for Android, from the Swift
  Android Workgroup, together with `swift-java` and Swift Java JNI Core for calling Swift from
  existing Kotlin and Java Android apps.
- **Swift 6.4** (September 2026) made Swift Build the default SwiftPM build system, unifying
  builds across Linux, macOS, and Windows. A Windows Workgroup formed in January 2026.
- Foundation improvements now land on macOS, iOS, Linux, and Windows simultaneously.

So a Swift core can fill the role a Kotlin Multiplatform core would have, using the toolchain
the Apple app already needs.

## Decision

`Packages/PanopKit` is kept strictly portable. Nothing under `Packages/PanopKit/Sources` may
import `UIKit`, `AppKit`, `SwiftUI`, `SwiftData`, `AVFoundation`, `AVKit`, `CoreMedia`, or
`VideoToolbox`.

Three supporting rules:

1. **Foundation only, with conditional imports.** `URLSession` is in `FoundationNetworking` and
   `XMLParser` in `FoundationXML` off-Apple, so both are guarded with `#if canImport(...)`.
2. **All I/O behind protocols.** `HTTPTransport` and `CatalogStore` let Linux substitute
   AsyncHTTPClient for `URLSession`, and Android substitute SQLite for SwiftData, without
   touching orchestration logic.
3. **No platform types in public signatures.** No `AVURLAsset`, no `CMTime`, no `@Model`.

Enforcement is mechanical: a SwiftLint `custom_rule` rejects the forbidden imports, and a Linux
CI job runs `swift test` against the package in a container on every push.

## Consequences

**SwiftUI stays Apple-only.** This decision shares logic, not UI. Android would get a Compose
UI calling into `PanopKit` over JNI; desktop would get its own. Parsing, the Xtream client,
EPG handling, catalog reconciliation, and the playback abstraction are shared. Views are not.

The enforcement is the point. A portability claim that nothing verifies decays within weeks,
and the breakage is invisible until someone attempts the port. The Linux CI job costs almost
nothing and fails the moment an Apple-only API appears.

Some friction is accepted in exchange: conditional imports are slightly awkward, and protocol
indirection for HTTP and storage is marginally more code than calling `URLSession` directly.
Both are cheap now and expensive to retrofit.

The Android SDK is new. This decision does not depend on it being production-ready today, only
on the core remaining portable so the option stays open.
