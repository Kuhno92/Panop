# Third-party notices

Panop is MIT licensed. It links and uses the components below.

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
- **License:** **GPL-3.0** by default. An LGPL license is available as a paid commercial option.
- **Source:** https://github.com/kingslay/KSPlayer
- **Use:** Metal-rendering playback engine
- **Status: BLOCKED. Not currently integrated.**

> **Verified 2026-09-29.** KSPlayer's README states it "defaults to the GPL license (requires
> open-sourcing your own project code)", with an LGPL variant sold separately.
>
> GPL-3.0 is incompatible with shipping Panop under MIT: linking it would force the combined
> work to be GPL-3.0. It is also incompatible with App Store distribution by anyone who is not
> the copyright holder, because GPLv3's terms conflict with the App Store's.
>
> **Resolution:** Panop carries a KSPlayer adapter in source, guarded by the
> `PANOP_ENABLE_KSPLAYER` compilation condition, but **does not link the dependency**. Official
> builds ship three engines: AVPlayer, VLCKit, and LumeEngine. The adapter compiles only for
> someone who adds the dependency themselves and accepts GPL-3.0 for their own build.
>
> Do not add KSPlayer to the project's package dependencies. Doing so relicenses the shipped
> binary as GPL-3.0 and makes App Store distribution untenable.
>
> This changes only if an LGPL commercial license is purchased from the maintainer, in which
> case update this entry and remove the guard.

### FFmpegKit
- **License:** LGPL-3.0 (with GPL build variants)
- **Source:** https://github.com/kingslay/FFmpegKit
- **Use:** would arrive transitively via KSPlayer
- **Status: not linked**, because KSPlayer is not linked.

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
