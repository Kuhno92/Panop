# Panop

A native IPTV player for Apple platforms. iPhone, iPad, Mac, and Apple TV from one codebase.

Panop connects to your own Xtream Codes provider or M3U playlist, indexes the catalog locally
for instant browsing, and plays streams through one of four interchangeable playback engines.

> **Panop ships no channels, streams, or content of its own.** You bring credentials from a
> provider you are entitled to use.

**Status: early development.** Not yet usable. See [Roadmap](#roadmap).

---

## Why four playback engines

IPTV is not just HLS. Providers serve raw MPEG-TS over HTTP, MKV VOD, HEVC nearly everywhere,
and occasionally RTSP. AVPlayer cannot play raw MPEG-TS at all, so any single-engine player
fails on a meaningful share of real streams.

| Engine | Best at | Tradeoff |
|---|---|---|
| **AVPlayer / AVKit** | HLS and VOD, native PiP, AirPlay, Now Playing, battery life | No raw MPEG-TS, narrow container support |
| **VLCKit** | Universal codec and container coverage | Large binary, weaker system integration |
| **LumeEngine** | Long-running live IPTV streams (FFmpeg 9) | Pre-1.0, API not frozen |

A fourth adapter for **KSPlayer** ships in source but is not linked, because KSPlayer is
GPL-3.0 and that is incompatible with both MIT licensing and App Store distribution. Build with
`PANOP_ENABLE_KSPLAYER` and add the dependency yourself if you accept GPL-3.0 for your own
build. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

You pick one in Settings, and Panop falls back through the others when a stream refuses to
start. Details, including how three separate copies of FFmpeg coexist in one binary, are in
[docs/engines.md](docs/engines.md).

---

## Requirements

- Xcode 26 or newer
- iOS 18+, iPadOS 18+, tvOS 18+, macOS 15+
- Swift 6

## Getting started

```bash
git clone --recurse-submodules <repo-url> Panop
cd Panop
Scripts/setup.sh
```

`setup.sh` installs git hooks and builds the vendored developer tools. **No Homebrew, Mint, or
global installs are needed**; SwiftLint, SwiftFormat, and lefthook are vendored through the
root `Package.swift` as SwiftPM plugins and pinned in `Package.resolved`, so every machine gets
identical versions.

```bash
# Fast loop: pure logic tests, no simulator, seconds not minutes
swift test --package-path Packages/PanopKit

# Build the app for every platform
Scripts/build-all-platforms.sh
```

---

## Architecture at a glance

```
Packages/PanopKit/     Portable core. Foundation only, no Apple-only frameworks.
  PanopCore            Value types
  PanopPlaylist        Streaming M3U/M3U8 parser
  PanopXtream          Xtream Codes client
  PanopEPG             XMLTV parser
  PanopCatalog         Import orchestration
  PanopPlayback        Engine abstraction

Panop/                 Apple app target. SwiftUI + SwiftData.
  Models/              @Model types and the two ModelContainers
  Views/Player/        The four engine adapters
```

Two things are worth knowing up front:

**The core is portable on purpose.** `PanopKit` imports nothing Apple-specific, so the same
logic can later back an Android, Windows, or Linux UI. Swift 6.3 shipped an official Android
SDK and Swift 6.4 unified builds across Linux, macOS, and Windows. Only the UI would be
rewritten, since SwiftUI stays Apple-only. A SwiftLint rule and a Linux CI job enforce this,
because an unverified portability claim decays quickly.

**Two SwiftData containers, not one.** The catalog is local-only; user state mirrors to
CloudKit. CloudKit forbids the uniqueness constraints and relationships a catalog needs, and a
single mirrored container re-runs every live `@Query` during import, which freezes tvOS.

Full detail in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), with decisions recorded in
[docs/adr/](docs/adr/).

---

## Roadmap

- [x] Repo scaffolding, docs, vendored tooling
- [ ] `PanopKit`: M3U parser and Xtream client with tests
- [ ] App target building on iOS, tvOS, and macOS
- [ ] Catalog browsing backed by SwiftData
- [ ] Playback: AVPlayer, then VLCKit, then LumeEngine
- [ ] EPG and TV guide
- [ ] CloudKit sync for favourites and watch progress

Not planned for v1: VPN integration (see
[ADR 0006](docs/adr/0006-no-vpn-in-v1.md) for why auto-enabling a VPN is not possible on Apple
platforms), and non-Apple UIs.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). If you are using an AI coding agent, point it at
[AGENTS.md](AGENTS.md) first; it documents the invariants that are expensive to rediscover.

## License

MIT, see [LICENSE](LICENSE). Third-party components and their licenses are listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
