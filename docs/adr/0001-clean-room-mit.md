# 0001. Clean-room implementation under MIT

**Status:** accepted; the licence part is superseded by ADR 0010 (GPL-3.0 from 2026-10-06). The clean-room rule stands.

## Context

`reference/` contains two third-party projects kept for occasional design reference:

- **Lume** (`github.com/bilipp/Lume`), a shipping Apple IPTV player, licensed **AGPL-3.0**
- **LumeEngine** (`github.com/bilipp/LumeEngine`), an FFmpeg 9 playback engine, licensed **MIT**

Lume solves nearly the same problem Panop does, which makes copying from it tempting.

## Decision

Panop is **MIT** licensed and written clean-room. Lume may be read to understand an approach.
Its code is never copied, in whole or in part, including scripts and configuration.

LumeEngine, being MIT, may be consumed as a dependency with attribution.

`reference/` is gitignored and is never part of the build graph.

## Consequences

AGPL-3.0 is strong copyleft. Deriving from Lume would force Panop to be AGPL and to publish all
source. More sharply, a third party cannot ship AGPL code on the App Store: the license's terms
conflict with the App Store's, and only the original copyright holder can resolve that by
granting Apple separate terms. Panop's author is not that copyright holder, so an AGPL Panop
would be effectively undistributable through Apple's store.

MIT keeps Panop open source, App Store shippable, and free of that conflict.

Practically this means re-deriving some solved problems. That is accepted. Where a technique is
genuinely necessary, such as the KSPlayer framework fixups, it is re-implemented from an
understanding of the underlying platform requirement rather than transcribed.

Every third-party dependency records its license in `THIRD-PARTY-NOTICES.md` in the same commit
that adds it.
