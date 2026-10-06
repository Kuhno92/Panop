# Third-party notices

Panop is GPL-3.0 licensed (see docs/adr/0010-link-ksplayer-gpl.md). It links and uses the components below.

**This file is the single source of truth for Panop's third-party licensing.** Any new
dependency must be added here in the same commit that introduces it.

---

## Runtime dependencies

### VLCKit
- **License:** LGPL-2.1-or-later
- **Source:** https://code.videolan.org/videolan/VLCKit
- **Use:** universal playback engine

LGPL requires that users be able to replace this component. VLCKit is consumed as a dynamic
xcframework and is **not** statically linked into Panop's binary. That must remain true.
VLCKit bundles FFmpeg, statically linked inside `libvlccore` with hidden symbol visibility.

- **Status:** integrated. Pinned to exactly **4.0.0-a24**, through SwiftPM
  (`https://code.videolan.org/videolan/VLCKit.git`). This is a pre-release: VLCKit 4 is the only
  line distributed as a Swift package, and the stable 3.7.x line is CocoaPods-only.
- **Binary:** a prebuilt xcframework downloaded by SwiftPM from download.videolan.org (about
  112 MB per macOS slice in the app, and several hundred MB in the package checkout).
- **Linking, verified:** the app links `@rpath/VLCKit.framework` dynamically and embeds it as its
  own framework. No libvlc symbols are in the app binary. This is what lets a user replace the
  component, as the LGPL requires.

### KSPlayer
- **License:** **GPL-3.0** (an LGPL licence is available from the maintainer as a paid option)
- **Source:** https://github.com/kingslay/KSPlayer, pinned to 2.3.4
- **Use:** FFmpeg-based playback engine with a Metal renderer, on all four platforms
- **Linking:** through `Packages/KSPlayerBridge`, a dynamic library built with library evolution, so its FFmpeg
  modules stay out of the app's compile. It is why Panop as a whole is GPL-3.0. On macOS its frameworks are rebuilt in the versioned layout at build time
  (`Scripts/deepen-frameworks.sh`).

### FFmpegKit
- **License:** LGPL-3.0 (with GPL build variants)
- **Source:** https://github.com/kingslay/FFmpegKit, 6.1.4
- **Use:** KSPlayer's FFmpeg and its libraries (dav1d, libass, gnutls, and others), linked through KSPlayer

### LumeEngine
- **License:** MIT
- **Copyright:** (c) 2026 Philipp Bischoff
- **Source:** https://github.com/bilipp/LumeEngine
- **Use:** FFmpeg 9 playback engine for long-running IPTV streams

Vendored as a git submodule at `vendor/LumeEngine` and referenced as a local path dependency.
This is required for correctness, not preference; see [docs/engines.md](docs/engines.md).

LumeEngine bundles **FFmpeg 9.0.x under LGPL**. Its product is dynamically linked to preserve
relinkability, and that must remain true.

- **Pinned:** tag `v0.2.2`, commit `069a818`. Its FFmpeg comes from a checksum-pinned xcframework
  the package downloads from its own GitHub release. Its own notices and the LGPL text are in
  `vendor/LumeEngine/THIRD-PARTY-NOTICES.md` and `vendor/LumeEngine/LICENSES/`.
- **Linking, verified:** the app links `@rpath/LumeEngine.framework` dynamically and embeds it in
  `Contents/Frameworks` through an explicit Embed Frameworks phase, code-signed on copy. Without
  that phase the build succeeds and the app cannot launch anywhere but the machine that built it.

### AetherEngine
- **License:** LGPL-3.0 **with an Apple Store / DRM exception** (permits distribution through the App Store and TestFlight where LGPL sections 4 to 6 would otherwise conflict)
- **Source:** https://github.com/superuser404notfound/AetherEngine
- **Use:** FFmpeg demuxing with VideoToolbox decoding; plays raw MPEG-TS and the containers AVPlayer refuses; keeps a rewindable window of a live stream

Pinned to exactly **7.27.2** through SwiftPM. Its obligations are the same kind as VLCKit's: ship the licence
texts, tell users they hold LGPL rights, keep the source public (and publish any change made to the engine; none is
made), and keep its FFmpeg frameworks dynamic and replaceable. They are: **FFmpegBuild** 3.6.0
(https://github.com/superuser404notfound/FFmpegBuild), dynamic frameworks under LGPL-2.1-or-later with no GPL
components, embedded in `Contents/Frameworks` (and the iOS and tvOS equivalents) as `AetherLib*.framework`.
AetherEngine's other dependency, **SMBClient** (MIT), is only used by its separate `AetherEngineSMB` product,
which Panop does not link.

**LibDovi is replaced by a stand-in.** AetherEngine depends on `libdovi` (MIT, Dolby Vision RPU parsing), a static
xcframework with a module map, as LumeEngine's FFmpeg is. Xcode writes both module maps to the same path and the
build stops with "Multiple commands produce .../include/module.modulemap". `Packages/LibDovi` is a package of the
same name and product with the same C interface (the part AetherEngine calls) whose functions do nothing, so it takes
the real one's place in the build. The effect: Dolby Vision profile 7 is not converted to profile 8.1 and plays as its
HDR10 base layer, as it does in a player without libdovi. Profiles 5 and 8 are unaffected. The stand-in is Panop's own
code under the MIT licence; no libdovi code is in it. See [docs/engines.md](docs/engines.md).

---

## Developer tooling

Not linked into the shipped app. Vendored via the root `Package.swift`.

| Component | License | Source |
|---|---|---|
| SwiftLint | MIT | https://github.com/realm/SwiftLint |
| SwiftLintPlugins | MIT | https://github.com/SimplyDanny/SwiftLintPlugins |
| SwiftFormat | MIT | https://github.com/nicklockwood/SwiftFormat |
| lefthook | MIT | https://github.com/evilmartians/lefthook |
| lefthook-plugin | MIT | https://github.com/csjones/lefthook-plugin |

---

## Online services

Not code in the build, but data the app fetches.

| Service | Use | Terms |
|---|---|---|
| Simkl (https://simkl.com) | Public trending and disc-release lists, and rows made from them (Top Box Office, Best of Netflix and the like), shown with Simkl's own colored icon (the brand asset it provides at us.simkl.in/img_favicon/v2/favicon-192x192.png, in `Panop/Assets.xcassets/SimklLogo.imageset`) at the start of each heading, the word Simkl kept in the trending rails' titles, a one-line credit under the rails, and a link to each title's Simkl page | https://api.simkl.org/api-rules: free for non-commercial apps and for commercial apps earning under $150 a month; above that a commercial licence is required. All Simkl code is in `PanopSimkl`, which can be dropped. |

---

## Not a dependency

`reference/` holds clones kept for occasional design reference. They are gitignored, are not
part of the build graph, and contribute no code to Panop.

**`reference/Lume` is AGPL-3.0.** No code from it appears in Panop, and none may be added. See
[ADR 0001](docs/adr/0001-clean-room-mit.md).
