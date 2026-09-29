# Panop Architecture

Panop is a native IPTV player for Apple platforms. It connects to a user's own Xtream Codes
provider or M3U playlist, indexes the catalog locally for instant browsing, and plays streams
through one of four interchangeable playback engines.

Panop ships no content. Users bring their own provider credentials.

**Status:** in development. This document describes the target architecture and the reasoning
behind it. `docs/adr/` records individual decisions; where the two disagree, the ADRs win.

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
│  Views/Player/   Four engine adapters + shared overlay       │
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
app-target concern, and the four adapters live in `Panop/Views/Player/`.

Reconnect policy, backoff, and engine fallback live in the shared coordinator above the
adapters, never inside one. Four engines report failure four different ways; duplicating
policy across them guarantees drift.

### The FFmpeg coexistence problem

Three of the four engines each bundle their own FFmpeg. They coexist through packaging, not
linker flags, and the mechanism differs per engine. This is subtle enough to have its own
document: see `docs/engines.md`. The short version is that **LumeEngine must be vendored as a
git submodule and referenced as a path dependency**, because consuming it by URL silently
disables the library-evolution flag that isolates its FFmpeg symbols.

---

## 6. Sync

CloudKit private database via SwiftData mirroring. No backend to run, no accounts to manage,
private by default, and free.

The tradeoff is that this is Apple-only. When Android arrives it will need either a bridge or
a server-backed sync provider. That was accepted deliberately: building and operating a sync
backend before the player works is premature, and the cloud container's contents are small and
well-defined enough to migrate later.

---

## 7. Deliberately out of scope for v1

- **VPN integration.** Auto-enabling a VPN on launch is not possible on Apple platforms for any
  tunnel the app does not itself provide, and shipping one requires a Network Extension, an
  organization developer account, and heightened App Store review. See
  `docs/adr/0006-no-vpn-in-v1.md`.
- **Android, Windows, Linux UIs.** The core is kept portable for them; no UI work is planned yet.
- **DRM.** IPTV streams are effectively never DRM protected, so no Widevine or FairPlay.

---

## 8. Repository layout

```
AGENTS.md              Agent and contributor guide. CLAUDE.md symlinks to it.
Package.swift          Vendors SwiftLint/SwiftFormat/lefthook. Builds nothing.
Packages/PanopKit/     The portable core.
vendor/LumeEngine/     Git submodule, path dependency.
reference/             Gitignored third-party clones, design reference only.
Panop/                 App target sources. A synchronized Xcode group.
Scripts/               setup.sh, build-all-platforms.sh, engine framework fixups.
docs/adr/              Decision records.
```

The Xcode project uses file-system-synchronized groups, so adding a source file means writing
it to disk. There is no project file to edit and no `.pbxproj` merge conflict to resolve. This
is a meaningful ergonomic win for both humans and coding agents, and it is why the project file
stays small enough to review in a diff.
