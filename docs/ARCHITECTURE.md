# Panop Architecture

Panop is a native IPTV player for Apple platforms. It connects to a user's own Xtream Codes
provider or M3U playlist, indexes the catalog locally for instant browsing, and plays streams
through one of three interchangeable playback engines.

Panop ships no content. Users bring their own provider credentials.

**Status:** in development. This document describes the target architecture and the reasoning
behind it. `docs/adr/` records individual decisions; where the two disagree, the ADRs win.
The final section records what actually exists today.

This file is the source of truth. A shareable web version is published at
<https://claude.ai/code/artifact/4d498ded-c71c-4e45-bc29-84f306decb61>; when the two disagree,
this one wins.

---

## 1. Goals and constraints

| Goal | Consequence |
|---|---|
| iOS, iPadOS, tvOS, macOS from one codebase | One platform-adaptive SwiftUI target, `#if os(...)` for divergence |
| Snappy UI on constrained hardware | Streaming parsers, batched persistence, indexed queries |
| Broad stream-format coverage | Multiple playback engines, user-selectable |
| Settings and progress sync across devices | SwiftData with CloudKit mirroring |
| Core reusable for Android, Windows, Linux later | Logic isolated in a Foundation-only SwiftPM package |
| MIT licensed, clean-room | No code copied from copyleft sources |

Minimum versions are iOS 18, iPadOS 18, tvOS 18, and macOS 15, built with Swift 6.

The hardest constraint is not the UI. It is that real IPTV catalogs run to 80,000 entries and
XMLTV guides exceed 100 MB, while the weakest supported device is an Apple TV HD. Every data
decision below follows from that.

---

## 2. Layer overview

```
┌──────────────────────────────────────────────────────────────┐
│  Panop/ (Xcode app target)          Apple-only               │
│                                                              │
│  Views/          SwiftUI, platform-adaptive                  │
│  Views/Player/   Engine adapters + shared overlay            │
│  Models/         SwiftData @Model types, two ModelContainers │
│  Services/       Sync orchestration, image pipeline          │
└───────────────────────────┬──────────────────────────────────┘
                            │ depends on
┌───────────────────────────▼──────────────────────────────────┐
│  Packages/PanopKit/                 PORTABLE, Foundation only│
│                                                              │
│  PanopCore      Value types                                  │
│  PanopPlaylist  Streaming M3U/M3U8 parser                    │
│  PanopXtream    Xtream Codes client  (behind HTTPTransport)  │
│  PanopEPG       XMLTV pull parser                            │
│  PanopCatalog   Import orchestration (behind CatalogStore)   │
│  PanopPlayback  PlaybackEngine protocol, engine kinds        │
└──────────────────────────────────────────────────────────────┘
```

The dependency arrow points one way only. `PanopKit` never imports the app, never imports
SwiftData, and never imports an Apple-only framework.

---

## 3. The portable core

`PanopKit` is a local SwiftPM package holding everything that is not UI and not persistence.
It carries two properties that matter more than their cost:

**It tests without a simulator.** `swift test --package-path Packages/PanopKit` runs the entire
logic suite in seconds. Booting a tvOS simulator to test an M3U parser is a minutes-long loop
that nobody runs often enough, and both humans and coding agents benefit from the fast path.

**It compiles off-Apple.** Swift 6.3 (March 2026) shipped the first official Swift SDK for
Android, and Swift 6.4 unified SwiftPM builds across Linux, macOS, and Windows. So the same
core can back a Compose UI on Android through `swift-java` JNI, or a desktop UI on Windows and
Linux, without a second toolchain and without reimplementing parsing, the Xtream client, EPG
handling, or catalog reconciliation. Only the UI is rewritten, because SwiftUI stays Apple-only.

Three disciplines keep that true, all cheap now and expensive to retrofit:

1. **Foundation only, with conditional imports.** `URLSession` lives in `FoundationNetworking`
   and `XMLParser` in `FoundationXML` on non-Apple platforms, so both are guarded with
   `#if canImport(...)`.
2. **All I/O behind protocols.** `HTTPTransport` and `CatalogStore` mean Linux can swap
   `URLSession` for AsyncHTTPClient, and Android can swap SwiftData for SQLite, without
   touching orchestration logic.
3. **No platform types in public signatures.** No `AVURLAsset`, no `CMTime`, no `@Model`.

Enforcement is mechanical, not aspirational: a SwiftLint `custom_rule` rejects Apple-only
imports under `Packages/PanopKit/Sources`, and a Linux CI job runs the test suite in a
container on every push. Portability claims that nothing verifies decay within weeks.

See `docs/adr/0007-portable-core.md`.

---

## 4. Data layer

### Two ModelContainers, not one

Panop runs two separate SwiftData containers:

| | Catalog | Cloud |
|---|---|---|
| Contents | Channels, movies, series, EPG | Favorites, watch progress, settings, credentials |
| CloudKit | `cloudKitDatabase: .none` | `.private(...)` |
| `@Query` bound | Yes, exclusively | **Never** |
| Uniqueness | `@Attribute(.unique)` used freely | Forbidden |
| Relationships | Yes | None |

This split is forced by two independent constraints.

CloudKit mirroring **forbids** `@Attribute(.unique)`, requires every property to be optional or
defaulted, and disallows the relationships a catalog naturally needs. A catalog modelled under
those rules would be slow and awkward.

Separately, a single mirrored container re-evaluates every active `@Query` during CloudKit
import churn. With a large catalog on tvOS that is enough to freeze the UI. Splitting the
containers means catalog browsing is never affected by sync activity.

Provider credentials in the cloud container use `@Attribute(.allowsCloudEncryption)`.

See `docs/adr/0003-two-model-containers.md`.

### Handling large catalogs

- **Parsers stream.** The M3U parser reads in chunks and emits batches. An 80,000-entry
  playlist never exists as a single array.
- **An HLS manifest is a stream, not a playlist.** Both start with `#EXTM3U`, so a stream
  URL pasted as an "M3U link" used to import its variant lines as bogus channels. The
  importer checks the first 64 KB for HLS-only tags and, if found, makes one channel that
  plays the address itself. Relative entry addresses resolve against the playlist's URL;
  ones that still have no host are skipped and counted in `ImportReport.skippedEntries`.
- **Persistence batches.** Imports run on a background `ModelContext` with autosave disabled,
  saving once per batch.
- **Queries are indexed.** Every predicate and sort column carries an index.
- **Enrichment yields.** Background indexing pauses while sync, playback, or active browsing is
  in progress, because any background save forces a main-context merge that re-runs every
  live `@Query`.

---

## 5. Playback

Three engines ship, selected by the user in Settings, with an ordered fallback list:

| Engine | Strength | Cost |
|---|---|---|
| **AVPlayer / AVKit** | Native PiP, AirPlay, Now Playing, best battery | Cannot play raw MPEG-TS over HTTP, limited container support |
| **VLCKit** | Widest codec and container coverage | Large binary, no native PiP integration |
| **LumeEngine** | FFmpeg 9, purpose-built for long-running IPTV streams | Pre-1.0, unfrozen API |

A fourth adapter for **KSPlayer** exists in source behind the `PANOP_ENABLE_KSPLAYER`
compilation condition, with its dependency deliberately unlinked: KSPlayer is GPL-3.0, which
would relicense Panop and forfeit App Store distribution. See ADR 0002.

This matters because IPTV is not just HLS. Providers serve raw MPEG-TS over HTTP, MKV VOD,
HEVC almost everywhere, and occasionally RTSP. AVPlayer alone fails on a meaningful share of
real streams, which is why a single-engine design does not survive contact with real providers.

`PanopPlayback` defines the `PlaybackEngine` protocol, the event and error types, and
`PlaybackEngineKind` that drives the Settings picker. It contains **no view type and no
AVFoundation import**, which is what keeps it portable. Video presentation is a separate
app-target concern, and the adapters live in `Panop/Views/Player/`.

`PlaybackEngineKind.available` excludes any engine that is not linked, so a menu or fallback
order built from it can never offer something that cannot play. Prefer it over `allCases`.

Reconnect policy, backoff, and engine fallback live in the shared coordinator above the
adapters, never inside one. Each engine reports failure differently; duplicating policy across
them guarantees drift. An adapter that retries on its own also hides the failure from the
coordinator, which then cannot fall back.

### The FFmpeg coexistence problem

The non-Apple engines each bundle their own FFmpeg. They coexist through packaging, not linker
flags, and the mechanism differs per engine. This is subtle enough to have its own document:
see `docs/engines.md`. The short version is that **LumeEngine is vendored as a git submodule
and referenced as a path dependency**, because consuming it by URL silently disables the
library-evolution flag that isolates its FFmpeg symbols.

---

## 6. Sync

CloudKit private database via SwiftData mirroring. No backend to run, no accounts to manage,
private by default, and free.

The tradeoff is that this is Apple-only. When Android arrives it will need either a bridge or
a server-backed sync provider. That was accepted deliberately: building and operating a sync
backend before the player works is premature, and the cloud container's contents are small and
well-defined enough to migrate later.

---

## 7. Licensing shaped the build

Panop is MIT and written clean-room. Licensing is not a footnote here, because it has already
changed two decisions.

**KSPlayer was dropped from the shipped build.** It is GPL-3.0 by default, with LGPL sold
separately as a commercial license. Linking it would force the combined work to be GPL-3.0
rather than MIT, and would forfeit App Store distribution, because GPLv3's terms conflict with
the App Store's in a way only a copyright holder can resolve. The adapter is kept in source
behind `PANOP_ENABLE_KSPLAYER`, with the dependency deliberately absent, so the option survives
at near-zero cost if an LGPL license is bought later.

**VLCKit is LGPL and must stay dynamically linked.** That is a standing constraint, not a
one-off check.

`reference/` holds third-party clones for occasional design reference. It is gitignored and
contributes no code. One of them is AGPL-3.0: reading it to understand an approach is fine,
reproducing its expression would make Panop undistributable.

The practical rule: check a dependency's license before adding it, and record it in
`THIRD-PARTY-NOTICES.md` in the same commit. See `docs/adr/0001-clean-room-mit.md` and
`docs/adr/0002-four-playback-engines.md`.

---

## 8. Deliberately out of scope for v1

- **VPN integration.** Auto-enabling a VPN on launch is not possible on Apple platforms for any
  tunnel the app does not itself provide, and shipping one requires a Network Extension, an
  organization developer account, and heightened App Store review. See
  `docs/adr/0006-no-vpn-in-v1.md`.
- **Android, Windows, Linux UIs.** The core is kept portable for them; no UI work is planned yet.
- **DRM.** IPTV streams are effectively never DRM protected, so no Widevine or FairPlay.

---

## 9. Repository layout

```
AGENTS.md              Agent and contributor guide. CLAUDE.md symlinks to it.
Package.swift          Vendors SwiftLint/SwiftFormat/lefthook. Builds nothing.
Packages/PanopKit/     The portable core.
Panop/                 App target sources. A synchronized Xcode group.
Panop.xcodeproj/       Hand-authored, ~330 lines.
Scripts/               setup.sh, build-all-platforms.sh, check-portability.sh, test-app.sh, ...
docs/adr/              Decision records.
reference/             Gitignored third-party clones, design reference only.
vendor/LumeEngine/     Git submodule (v0.2.2), local path dependency, embedded dynamically.
```

The Xcode project uses file-system-synchronized groups, so adding a source file means writing
it to disk. There is no project file to edit and no `.pbxproj` merge conflict to resolve. This
is a meaningful ergonomic win for both humans and coding agents, and it is why the project file
stays small enough to review in a diff. See `docs/adr/0005-xcode-synchronized-groups.md`.

Developer tooling is vendored through the root `Package.swift` as SwiftPM plugins, so a clone
needs only Xcode's toolchain: no Homebrew, no Mint, no global installs, and every machine and
CI runner gets the versions pinned in `Package.resolved`. `Scripts/setup.sh` is the one
post-clone command.

---

## 10. Status

| Stage | State |
|---|---|
| Repo scaffolding, docs, vendored tooling | Done |
| `PanopKit`: PanopCore, PanopPlaylist, PanopPlayback | Done |
| `PanopXtream` (client, streaming list reader, `HTTPTransport`) | Done |
| `PanopEPG` (XMLTV parser, gzip, rolling window) | Done |
| `PanopCatalog` (importer, `CatalogStore` protocol, in-memory store) | Done, 175 tests passing across the package |
| Xcode project and app target | Builds and launches on macOS, iOS and tvOS |
| Playback coordinator and the AVPlayer adapter | Done: 23 coordinator tests in 0.2 s, and the adapter tested against real AVFoundation on macOS, iOS and tvOS |
| VLCKit adapter (4.0.0-a24) | Done: plays raw MPEG-TS over HTTP; coordinator fallback from AVPlayer verified on real transport-stream bytes on macOS |
| LumeEngine adapter (v0.2.2) | Done: plays raw MPEG-TS and HLS; coordinator fallback from AVPlayer verified; macOS and iOS |
| `SwiftDataCatalogStore`, `PanopTests` target | Done, 22 tests passing on macOS, iOS and tvOS |
| Playlist import flow: add, Keychain credentials, background sync, playlists screen | Done at the service level (43 app tests); screens launch but are not yet driven by UI tests |

Two verification gaps worth knowing about, both environmental rather than design problems:

- **The engine picker is verified on tvOS only.** Driving the Apple TV simulator by keyboard
  confirmed Settings renders and the picker lists exactly AVPlayer, VLC and LumeEngine, with
  KSPlayer absent as ADR 0002 requires. The same screen on iOS has not been opened: `simctl`
  has no tap command and synthetic clicks fail with System Events error -25204, so only the
  launch screen is confirmed there. A UI test target would close this properly.
- **The Linux portability check has not run locally.** It needs Docker. The SwiftLint custom
  rule covers the common case (an Apple-only import) but not a Foundation API that is missing
  off-Apple. The CI job covers it properly.

CloudKit mirroring is currently disabled in `PanopContainers`. Turning it on needs a Developer
Program team and a real iCloud container identifier; without those the app fails to launch
rather than degrading, so the switch belongs in the same change that adds the entitlement.
