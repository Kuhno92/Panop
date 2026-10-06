# Which engine plays which stream

Measured on **2026-10-05** against one real Xtream provider (about 1,000 live channels, 10,000 films, 1,400 series), one
stream at a time because the provider allows a single connection. The test is `PanopTests/RealProviderEngineMatrix.swift`;
it is off unless `PANOP_DEV_XTREAM` and `PANOP_ENGINE_MATRIX` are set in the environment (the login is never written
down), and it needs the app to be allowed on the local network. A stream counts as **played** only when the engine says
it is playing and its position then moves by a second.

## What the provider serves

| | |
|---|---|
| Live channels | Raw MPEG-TS over HTTP, H.264 (interlaced) with AAC, once AC3. The `.m3u8` address returns the **same raw TS**, not an HLS playlist. Many channels are down or answer 503. |
| Films | 7,923 MKV, 2,456 MP4. MKV samples: H.264 or HEVC, AAC, AC3 or DTS, SRT or ASS subtitles. MP4 samples: H.264 and AAC. |
| Episodes | MKV (519 of 519 checked), same codecs as the MKV films |

## Result

| Stream | AVPlayer | LumeEngine | AetherEngine | VLC | KSPlayer (2026-10-06) |
|---|---|---|---|---|---|
| Live, raw MPEG-TS | refuses (`unsupportedFormat`), 3 of 3 | plays, 3 of 3, first picture about 2.5 to 3 s | **crashes the process** (SIGSEGV in its deinterlace filter), 2 of 2 attempts; also with its software deinterlacer | plays, 3 of 3, about 3 to 6 s | plays, 2 of 2, moving after 3.2 and 4.8 s |
| Live, the `.m3u8` address (raw TS) | fails (CoreMedia -1264) | no answer in 25 s | fails (`custom source probe failed`) | plays | plays, 1 of 1, moving after 2.8 s |
| MP4 films and episodes | plays, 5 of 5 | plays, 5 of 5 | plays, 5 of 5 | plays, 5 of 5 | plays, 4 of 4 films, moving after 3.6, 3.8, **9.9 and 11.4 s** |
| MKV films | refuses (`unsupportedFormat`), 6 of 6 | plays, 6 of 6, 0.5 to 1.5 s to open | plays, 6 of 6, 0.6 to 6.4 s to open | plays, 6 of 6, about 3.5 to 12 s to first motion | plays, 6 of 6, moving after 2.3 to 3.6 s |
| MKV episodes | refuses, 3 of 3 | plays, 3 of 3 | plays | plays, 3 of 3 | plays, 4 of 4, moving after 1.8 to 4.1 s |

Times are "opened" plus "moving after" from a debug build, so they compare engines but are not absolute.

## What the app does with it

`PlaybackEngineKind.defaultPriority(for:)` (`PanopPlayback`, tested in `EnginePriorityTests`):

- **Not an Apple container** (MKV, raw TS): `LumeEngine, VLC, KSPlayer, AetherEngine, AVPlayer`. AVPlayer is last, not first, since it refuses these outright.
- **Apple container** (MP4, HLS, or no extension): `AVPlayer, LumeEngine, VLC, KSPlayer, AetherEngine`.
- **KSPlayer after VLC, before AetherEngine** (measured 2026-10-06, same provider, macOS): it played all 17 streams, including the `.m3u8` live address that Lume and Aether could not play, and did not fail or crash once. It is never the fastest to a moving picture: live 2.8 to 4.8 s (Lume about 2.5 to 3 s), MKV 1.8 to 4.1 s (Lume 1.4 to 2.7 s, VLC 1.8 to 12 s), MP4 3.6 to 11.4 s (AVPlayer 1.8 s, VLC about 3 s; two of four MP4 films took about 10 s, which was not looked into). Its open step returns in 0.1 s, so the time to first picture is in "moving after".
- **AetherEngine after VLC**: it was only about half a second faster on films (MKV about 5.3 s against VLC's 5.7 s to a moving picture on average), and the deinterlacing code that crashed it runs for any interlaced source, not only live TV. AVPlayer first keeps picture in picture, AirPlay and battery life where it works.
- **Live TV never includes AetherEngine** in the automatic order, because it crashed. A person can still choose it in Settings, where it is labelled experimental.
- The person's own choice, when set, always goes first. The engine that last played a given title is remembered and tried first next time.

## Limits of this test

- One provider, and 3 to 6 streams per kind per engine. The live sample was all H.264 and AAC; HEVC live, AC3-only or MPEG-2 channels were not tried.
- The AetherEngine crash is reproduced in a debug build of the app; the crash site is inside the engine's FFmpeg filter teardown
  (`DeinterlaceFilter.ensureGraph` to `avfilter_free`), not in Panop's code. It should be reported upstream; see the roadmap.
- The `.m3u8` row says nothing about real HLS, which this provider does not serve. AVPlayer plays real HLS.
- macOS only. iOS and tvOS were not run against the provider, and KSPlayer's times may differ on Apple TV.
- KSPlayer: one run, 3 live, 10 film and 4 episode streams; the MP4 delays (9.9 s and 11.4 s) were not repeated.
