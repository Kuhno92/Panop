# 0010. Link KSPlayer, and license Panop as GPL-3.0

**Status:** accepted 2026-10-06. Supersedes the KSPlayer amendment of ADR 0002 and the MIT choice of ADR 0001
for everything released from here on.

## Context
KSPlayer is GPL-3.0 (its LGPL variant is sold separately). ADR 0002 kept its adapter out of the build so that Panop
could stay MIT and App Store-eligible. The project owner decided that having KSPlayer as a fifth engine is worth
more than the MIT licence, and that Panop stays fully open source, which is what the GPL asks of a work that
includes GPL code.

## Decision
- KSPlayer 2.3.4 is linked, through `Packages/KSPlayerBridge`, on **iOS, iPadOS and tvOS**.
- Panop as a whole is **GPL-3.0** (`LICENSE`). Its own source stays public. Earlier MIT releases stay MIT.
- It is the **last** engine in the default order: it has not been measured on a real provider yet.

## Why a bridge package
FFmpegKit (KSPlayer's FFmpeg 6) exports C modules named `Libavcodec`, `Libavutil` and so on. AetherEngine's FFmpeg
(`AetherLibavcodec`...) and LumeEngine's (`CFFmpeg`) define the same C types, and one compile that sees both fails
(`'AV_CODEC_ID_AHX' from module 'AetherLibavcodec' is not present in definition of 'enum AVCodecID' in module
'Libavcodec'`). `KSPlayerBridge` is a local package built with `-enable-library-evolution` and internal imports, so its
interface names no KSPlayer or FFmpeg type and the app never loads those modules. It must stay a path dependency
(SwiftPM refuses unsafe flags in a versioned one), exactly like `vendor/LumeEngine`.

## Not on macOS
FFmpegKit's macOS frameworks are packaged with `Info.plist` at the bundle root, which Xcode refuses to embed on macOS
("expects Versions/Current/Resources/Info.plist"). The bridge is linked with a platform filter (iOS, tvOS); on macOS
the registry reports no adapter and the coordinator skips the engine.

## Consequences
- **App Store.** The GPL and the App Store's terms have a long history of conflict (VLC changed licence over it).
  Open source alone does not settle it; take advice before submitting. Ad hoc and sideloaded builds are unaffected.
- Contributors' code is contributed under GPL-3.0. Dependencies must be GPL-compatible: LGPL and MIT are. AGPL
  (`reference/Lume`) stays off limits as a source of code.
- VLCKit, LumeEngine, AetherEngine and LibDovi keep their licences, listed in THIRD-PARTY-NOTICES.md.
