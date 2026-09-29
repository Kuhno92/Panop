# Panop — AI Agent Guide

Panop is a native IPTV player for Apple platforms (iOS 18+, iPadOS 18+, tvOS 18+, macOS 15+),
written in Swift 6 and SwiftUI. Playback runs through three interchangeable engines the user
picks in Settings: AVPlayer, VLCKit, and LumeEngine. A fourth adapter for KSPlayer exists in
source but is **not linked**, because KSPlayer is GPL-3.0; see Licensing below.

`CLAUDE.md` is a symlink to this file. One guide, every agent.

---

## Current status

The repo is being built up in stages. **Only check off what actually exists**; do not assume a
command works because it is documented below.

- [x] Repo skeleton, docs, lint tooling, ADRs
- [x] `Packages/PanopKit`: PanopCore, PanopPlaylist, PanopPlayback, PanopXtream, PanopEPG, PanopCatalog (188 tests passing)
- [x] `Panop.xcodeproj` and the app target (builds and launches on **macOS and iOS**)
- [x] `SwiftDataCatalogStore` and the `PanopTests` target (43 tests, passing on macOS, iOS and tvOS)
- [ ] Engines: AVPlayer, then VLCKit, then LumeEngine (KSPlayer stays unlinked)
- [x] Playlist import wired to the catalog container: add by Xtream login, M3U link or M3U file, Keychain credentials, background sync. The screens launch and are covered by service-level tests, but have not been driven by hand or by UI tests yet

`docs/ROADMAP.md` is the full feature list, ordered into milestones and traced back to the
original requirements. **Check it before starting work**, and tick items there as they land.
It exists so that features raised once in conversation are not lost between sessions.

### Platform components and disk

iOS 26.5 is installed and verified. **tvOS is not yet**, so a tvOS destination still fails with
"platform is not installed" before compiling anything. That is an environment gap, never a
project fault. Install it once:

```bash
xcodebuild -downloadPlatform tvOS     # ~8 GB, and it needs room to expand
```

Simulator runtimes are large. Before downloading a platform, check free space and drop runtimes
older than the deployment target, since a runtime below iOS 18 cannot run Panop at all:

```bash
xcrun simctl runtime list                 # sizes and identifiers
xcrun simctl runtime delete <identifier>  # proper removal; never rm -rf these
```

`~/Library/Developer/Xcode/iOS DeviceSupport` is also safe to delete and regenerates the next
time a physical device is connected.

---

## Setup

```bash
Scripts/setup.sh        # once after cloning. Installs git hooks, warms the vendored tools.
```

All developer tooling (SwiftLint, SwiftFormat, lefthook) is vendored through the root
`Package.swift` as SwiftPM plugins. **You need only Xcode's toolchain.** Do not add Homebrew,
Mint, or global installs to any script or CI job: the whole point is that every machine and
runner gets byte-identical tool versions, pinned in `Package.resolved`.

Note this machine's Homebrew is an Intel build at `/usr/local` and several of its binaries
fail with "bad CPU type" (`gh` and `timeout` among them). Do not reach for them.

---

## Commands

```bash
# Fast loop. Pure-logic tests, no simulator, seconds not minutes. Prefer this.
swift test --package-path Packages/PanopKit

# One target only
swift test --package-path Packages/PanopKit --filter PanopPlaylistTests

# Lint / format (setup.sh symlinks these into .build/tools/bin)
.build/tools/bin/swiftlint lint --strict --quiet
.build/tools/bin/swiftformat .

# Verify the core still builds off-Apple. Run before any PanopKit PR.
Scripts/check-portability.sh

# App build, all three platforms
Scripts/build-all-platforms.sh

# Parallel work: a worktree wired for hooks, submodules and a private DerivedData
Scripts/worktree.sh add feat/epg-parser
Scripts/worktree.sh remove feat/epg-parser

# App tests (SwiftData, so they cannot live in the portable package). ~10 s on macOS
Scripts/test-app.sh [macos|ios|tvos]

# Catalog import benchmarks: Release build, macOS, prints a results table
Scripts/test-app.sh --benchmark

# Reclaim disk from build caches. Dry run by default; keeps the hook tooling
Scripts/clean-caches.sh [--apply]
```

No tvOS simulator runtime is installed on this machine, so the tvOS step in
`build-all-platforms.sh` is a compile-only check against a generic destination.
Install one with `xcodebuild -downloadPlatform tvOS` to launch on Apple TV.

### Always share the package clone directory

Any `xcodebuild` invocation that sets `-derivedDataPath` **must** also set
`-clonedSourcePackagesDirPath ~/Library/Developer/Panop-SharedSPM`:

```bash
xcodebuild build -project Panop.xcodeproj -scheme Panop \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -clonedSourcePackagesDirPath ~/Library/Developer/Panop-SharedSPM
```

**Why:** VLCKit's xcframework alone is ~865 MB and KSPlayer drags in FFmpegKit's. Without a
shared clone dir, every DerivedData directory re-downloads and re-expands the whole graph,
several GB each. A handful of parallel builds will fill your disk. It is also faster and avoids
a checkout race that breaks multi-platform archiving.

---

## Performance is the product

Panop has to feel instant. Every implementation decision is weighed against that first, ahead of
convenience and ahead of elegance. The UI must stay snappy on the weakest supported device (an
Apple TV HD), and nothing the user does should wait on something they cannot see.

Treat these as defaults when writing or reviewing code:

- **The main thread is for drawing.** No parsing, decoding, disk or network I/O, or catalog work
  on it. Anything that can take more than a frame goes to a background task, and the UI shows
  something immediately while it runs.
- **Never make the user wait for a full result.** Stream and batch (see Large catalogs), show the
  first rows as they arrive, and render from local data before touching the network.
- **Bound every query.** A fetch has a limit, a predicate that narrows it in SQL, and an index
  behind both. An unbounded fetch, or a sort that defeats the limit, is a bug even when the
  screen looks right, because it only shows up at 80,000 rows.
- **Channel zapping is the metric that matters.** Time from selecting a channel to the first
  frame is what users judge an IPTV app on. Do not add work to that path; see `docs/ROADMAP.md`
  M3 for the levers.
- **Keep views cheap.** No sorting, filtering or formatting inside `body`. Lists are lazy, images
  are downsampled and cached, and state that changes often is scoped so it does not re-render a
  whole screen.
- **Memory is a performance budget.** On tvOS an over-budget app is killed, with no swap and no
  warning. Flat memory during import matters as much as speed.
- **Measure, do not guess.** Before an optimisation and after it, and never in a Debug build,
  where `-Onone` makes the numbers fiction. If a change touches a hot path (parsing, import,
  browse queries, playback start), say what was measured in the PR.
- **A regression is a bug.** If a change makes a screen, an import or a channel change slower,
  fix it or justify it explicitly. "It still works" is not the bar.

When speed and simplicity pull apart, choose speed, then leave a comment saying why, because the
fast version is usually the surprising one.

---

## Architecture

```
Packages/PanopKit/     PORTABLE core. Foundation only. No Apple-only frameworks.
├── PanopCore          Value types shared by everything
├── PanopPlaylist      Streaming M3U/M3U8 parser
├── PanopXtream        Xtream Codes client, behind HTTPTransport
├── PanopEPG           XMLTV pull parser
├── PanopCatalog       Import/reconcile orchestration, behind CatalogStore
└── PanopPlayback      PlaybackEngine protocol + PlaybackEngineKind

Panop/                 Apple app target. SwiftUI + SwiftData.
├── Models/            @Model types, the two ModelContainers, SwiftDataCatalogStore
├── Services/          Sync orchestration, image pipeline
└── Views/Player/      The engine adapters live here, not in PanopKit
```

`docs/ARCHITECTURE.md` is authoritative for design questions, and `docs/adr/` records why each
significant decision was made. **Check those before proposing a structural change.**

---

## Invariants

These are requirements, not style preferences. Each one was chosen for a reason, and breaking
it produces a failure that is expensive or slow to diagnose.

### PanopKit must not import Apple-only frameworks

No `UIKit`, `AppKit`, `SwiftUI`, `SwiftData`, `AVFoundation`, `AVKit`, `CoreMedia`, or
`VideoToolbox` anywhere under `Packages/PanopKit/Sources`.

**Why:** the core is meant to drive Android, Windows, and Linux UIs later (Swift 6.3 shipped an
official Android SDK; see `docs/adr/0007-portable-core.md`). Portability rots silently within
weeks unless enforced. Two mechanisms catch violations: a SwiftLint `custom_rule`, and a Linux
CI job that runs `swift test` in a container.

Use `#if canImport(FoundationNetworking)` for `URLSession` and `#if canImport(FoundationXML)`
for `XMLParser`. Both live in separate modules off-Apple, and omitting the guard breaks the
Linux build while compiling fine on macOS.

### LumeEngine is a submodule, NEVER a URL dependency

It must be referenced as a local path package at `vendor/LumeEngine`.

**Why:** LumeEngine isolates its FFmpeg 9 with `-enable-library-evolution`, declared through
`.unsafeFlags`. SwiftPM forbids unsafe flags in version-resolved dependencies, so its manifest
gates the flag on `#filePath` not containing `/checkouts/`. Consumed by URL the flag silently
drops, its `CFFmpeg` module leaks into the app's compile, and it collides with the FFmpeg
KSPlayer brings in, producing `enum AVPixelFormat` redefinition errors.

**This is the mistake an agent is most likely to make.** "Simplify the submodule to a version
dependency" looks like tidying and is a build break. Do not do it. See `docs/engines.md`.

### Every test ModelConfiguration sets `cloudKitDatabase: .none`

**Why:** the catalog container is local-only and uses uniqueness constraints on its small tables,
which CloudKit forbids. With the default `.automatic`, tests crash on any host that carries
iCloud entitlements. `PanopContainers.makeCatalog` already sets `.none`; build test containers
through it.

### Never bind `@Query` against the cloud container

Panop runs two `ModelContainer`s. The catalog container is local-only and is what every
`@Query` targets. The cloud container mirrors user state to CloudKit and is read through
explicit fetches.

**Why:** a single mirrored container re-evaluates every active `@Query` during CloudKit import
churn. On tvOS that is enough to freeze the UI. See `docs/adr/0003-two-model-containers.md`.

### Do not add retry or reconnect logic to an engine adapter

Reconnect policy, backoff, and engine fallback belong in the shared player coordinator, one
level above the adapters.

**Why:** each engine reports failure differently, and duplicating policy across them guarantees
they drift. An adapter that retries on its own also hides the failure from the coordinator,
which then cannot fall back. LumeEngine in particular is explicit that it never retries on its
own schedule.

---

## Platform gotchas

### tvOS
- `Color.accentColor` resolves to white on tvOS. Never use it for fills or tints.
- Focus targets must span the full width of a row, or vertical focus navigation skips them.
- `.onMoveCommand` runs inside the focus engine's animated context. Defer layout mutations
  with `Task { }`.

### Swift 6 concurrency
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set project-wide. Value types and DTOs used from
`nonisolated` contexts need an explicit `nonisolated` on **the type and every extension**.
Missing one produces an error far from the cause.

### Large catalogs
Real IPTV playlists run to 80,000 entries and XMLTV guides exceed 100 MB. Parsers stream and
emit batches; never materialize a whole playlist as one array. Persist in batches inside one
transaction with autosave disabled.

---

## Conventions

- **Commits:** Conventional Commits (`feat(player): ...`, `fix(epg): ...`, `docs: ...`).
  Branches mirror the type: `fix/epg-timezone-drift`.
- **Tests:** swift-testing (`import Testing`) for new tests. XCTest only where a framework
  requires it, such as UI tests and `measure`.

  Expect the pre-commit formatter to rewrite `@Test("some name") func someName()` into
  ``@Test func `some name`()`` using Swift 6.2 raw identifiers. That is SwiftFormat doing its
  job, not a mistake to revert. The displayed test name is unchanged.
- **Fixtures are never committed.** Generate them; large playlists and media files stay out of
  git. Generated fixtures belong in gitignored `Generated/` directories.
- **Comments explain why, not what.** If the reason is not surprising, omit the comment.

---

## Licensing

Panop is **MIT**. Two rules protect that:

1. `reference/` holds third-party clones for occasional design reference and is gitignored.
   **`reference/Lume` is AGPL-3.0. Never copy code from it**, not a function, not a script.
   Reading it to understand an approach is fine; reproducing its expression is not.
2. Any new third-party dependency must have its license recorded in `THIRD-PARTY-NOTICES.md`
   in the same commit that adds it. VLCKit is LGPL and must stay dynamically linked.

### Never add KSPlayer to the project's dependencies

KSPlayer is **GPL-3.0**. Linking it would relicense the shipped binary as GPL-3.0, which Panop
is not, and would forfeit App Store distribution, because GPLv3 conflicts with the App Store's
terms in a way only a copyright holder can resolve.

The adapter in `Panop/Views/Player/` is guarded by `PANOP_ENABLE_KSPLAYER` and compiles only
for someone who adds the dependency to their own build and accepts GPL-3.0 for it. **Seeing a
`PlaybackEngineKind.ksPlayer` case with no dependency is not an oversight to fix.** Adding the
package to make it build is a licensing violation, not a bug fix.
