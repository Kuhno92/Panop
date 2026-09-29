# 0002. Multiple user-selectable playback engines

**Status:** accepted, amended 2026-09-29 (KSPlayer licensing)

## Context

IPTV providers serve a far wider range of formats than Apple's media stack handles. Raw MPEG-TS
over HTTP is common and **AVPlayer cannot play it at all**. MKV VOD, HEVC, and occasional RTSP
are also routine. A single-engine player fails on a meaningful share of real streams.

Different engines also trade off differently. AVPlayer gives native Picture in Picture,
AirPlay, Now Playing, and the best battery life, but the narrowest format support. VLCKit plays
nearly anything but integrates poorly with the system. KSPlayer renders through Metal and
performs well on tvOS. LumeEngine is purpose-built for long-running live IPTV streams.

## Decision

Ship **three** engines (AVPlayer, VLCKit, LumeEngine), selectable in Settings, with an ordered
fallback list used when an engine fails to start a stream.

A fourth adapter for **KSPlayer** exists in source but its dependency is not linked. See the
amendment below.

`PanopPlayback` in the portable core defines the `PlaybackEngine` protocol, the event and error
types, and `PlaybackEngineKind`. The four adapters live in the app target under
`Panop/Views/Player/`, because they touch AVFoundation and UIKit/AppKit and the core must not.

Reconnect policy, backoff, and fallback ordering live in a coordinator above the adapters,
never inside one.

## Consequences

Significant integration cost, and three of the four engines bundle their own FFmpeg, which is
the most fragile part of the build. That problem and its resolution are documented separately
in `docs/engines.md`.

Binary size grows substantially. VLCKit's xcframework alone is around 865 MB before thinning.

Putting fallback policy in one coordinator rather than in each adapter is deliberate: four
engines report failure four different ways, and duplicated policy would drift apart.

Engines are added one at a time with a verified build between each, so a new FFmpeg is debugged
against a known-good state.

## Amendment, 2026-09-29: KSPlayer is GPL-3.0

KSPlayer was originally planned as a fourth shipped engine. Verification found it is
**GPL-3.0 by default**, with LGPL sold separately as a commercial license.

That is incompatible with Panop twice over. Linking it forces the combined work to be GPL-3.0,
so Panop could not be MIT. And GPLv3's terms conflict with the App Store's, which anyone who is
not the copyright holder cannot resolve, so it would also cost App Store distribution.

**Resolution.** The `PlaybackEngineKind` enum retains a `.ksPlayer` case and the adapter is
written, but it is guarded by the `PANOP_ENABLE_KSPLAYER` compilation condition and the
dependency is **not** added to the project. Official builds ship three engines. Someone
building from source may add the dependency and enable the flag, accepting GPL-3.0 for their
own build.

The cost of keeping the adapter is close to zero, and it preserves the option should an LGPL
commercial license be purchased later.

Nothing else in this ADR changes: the abstraction, the fallback coordinator, and the reasoning
for multiple engines all still hold. VLCKit and LumeEngine between them cover the formats
KSPlayer would have handled.
