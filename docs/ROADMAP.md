# Panop Roadmap

Everything Panop is meant to do, so nothing gets lost between sessions.

Two kinds of item appear here. **Asked for** items come from the original brief. **Surfaced**
items were not in the brief but are things an IPTV player cannot ship without, or that fell out
of a decision made later. Both are tracked, because the second kind is what usually gets
forgotten.

`docs/ARCHITECTURE.md` says how these are built and `docs/adr/` says why. This file only says
what and in what order.

---

## Requirements traceability

The original brief, and where each requirement is satisfied.

| # | Requirement | Status | Where |
|---|---|---|---|
| 1 | iOS, iPadOS, tvOS, macOS | Done | M0. Builds and launches on all three |
| 1b | Android, Windows, Linux | Deferred by design | Core kept portable (ADR 0007). No UI planned |
| 2 | Very modern UI | Not started | M4 |
| 3 | Snappy interface | Ongoing constraint | M1, M6. Streaming parser already done |
| 4 | Good streaming performance | Not started | M3, M6. Channel zapping is the metric that matters |
| 5 | Settings sync across devices | Not started | M5. CloudKit, currently disabled |
| 6 | VPN auto-enable on launch | **Cut from v1** | Not achievable as described. ADR 0006 |
| 7 | Live TV and VOD | Not started | M2 |
| 8 | M3U support | Done | M0. `PanopPlaylist`, tested at 8 chunk sizes |
| 8b | Xtream Codes API | Not started | M1 |

---

## M0 — Foundations

**Done.** Commits `d0065b3` through `283af68`.

- [x] Git repo, MIT licence, clean-room rule (ADR 0001)
- [x] Agent guide, architecture doc, seven ADRs, contributor guide
- [x] Vendored SwiftLint, SwiftFormat, lefthook. No Homebrew needed
- [x] `PanopCore`, `PanopPlaylist` (streaming M3U parser), `PanopPlayback` (engine protocol)
- [x] 31 tests running in 0.003s with no simulator
- [x] Xcode project with synchronized groups (ADR 0005)
- [x] Both SwiftData containers wired (ADR 0003)
- [x] Linux CI job and portability script (ADR 0007)

---

## M1 — Ingest and catalog

Getting a real provider's content into the app. Nothing else can be tested until this works.

- [ ] **`PanopXtream`** *(asked for)*. Client behind `HTTPTransport`, covering
      `get_live_streams`, `get_vod_streams`, `get_series`, `get_series_info`, `get_short_epg`,
      and the stream URL builders. Tests use a stub transport, no network.
- [ ] **`PanopEPG`** *(surfaced)*. XMLTV pull parser emitting batches, gzip support, and a
      rolling window rather than the whole guide. Guides exceed 100 MB.
- [ ] **`PanopCatalog`** *(surfaced)*. Import and reconcile orchestration behind `CatalogStore`,
      so Android can reuse it later.
- [ ] **`SwiftDataCatalogStore`** in the app target, implementing that protocol.
- [ ] **Playlist import flow**: add a playlist by URL, file, or Xtream credentials.
- [ ] **Incremental re-import**. Skip unchanged playlists by digest rather than reparsing 80,000
      entries every launch.
- [ ] **Credential storage in Keychain**, with `kSecUseDataProtectionKeychain` for macOS parity.

> Watch out: iCloud Keychain does not sync to tvOS. Anything that must reach an Apple TV goes
> through the CloudKit container instead.

---

## M2 — Browse and play

The first milestone where Panop is usable.

- [ ] **Live TV list** with provider groups *(asked for)*
- [ ] **Movies and Series** browsing, including episode lists *(asked for, VOD)*
- [ ] **Search** across the catalog. Needs SQLite FTS or bounded predicates with a fetch limit;
      an unbounded sort defeats the limit entirely.
- [ ] **Engine coordinator** *(surfaced)*: owns the ordered fallback list, reconnect and
      backoff. Never inside an adapter (ADR 0002).
- [ ] **AVPlayer adapter**. First real engine.
- [ ] **VLCKit adapter**. LGPL, must stay dynamically linked.
- [ ] **LumeEngine adapter**, vendored as a pinned submodule, never a URL dependency.
- [ ] **App-side facade over LumeEngine's `PlayerSession`** *(surfaced)*. Its `LumePlayer` facade
      exposes no event stream and keeps `session` private, so reconnect, PiP and Now Playing all
      need building on the lower-level type.
- [ ] **Player overlay** shared across engines: transport, track switching, engine indicator.
- [ ] **Resume playback** from a stored position. Pass it at load time; seeking an in-flight
      IPTV connection makes some providers drop the stream.

---

## M3 — Streaming performance

The brief called performance a key concept. For IPTV this concentrates in one number.

- [ ] **Fast channel zapping** *(asked for, as "streaming performance")*. Time from channel
      select to first frame is the metric users judge an IPTV app on. Levers: a pre-warmed
      second player instance, HTTP keep-alive to the provider, and caching resolved stream URLs.
- [ ] **Reconnect and backoff policy** on stall or IO error, distinguishing retryable failures
      from format rejections. `PlaybackError.isRetryable` already encodes the distinction.
- [ ] **Engine fallback on failure**, with the reason surfaced rather than a silent switch.
- [ ] **Playback QoE metrics** *(surfaced)*: join time, rebuffer ratio, exits before first
      frame, engine fallbacks. Flush at session boundaries only; periodic writes during playback
      cause hitching.
- [ ] **Picture in Picture and AirPlay** via AVPlayer; note the other engines cannot match this.
- [ ] **Now Playing and remote commands**, needed for the Apple TV Siri remote.
- [ ] **Background audio**. `UIBackgroundModes` is already set.

---

## M4 — Interface

- [ ] **Modern UI pass** *(asked for)*. Home with rails, hero, artwork.
- [ ] **tvOS focus engine work** *(surfaced)*. Full-width focus targets, no `Color.accentColor`
      for fills, layout mutations deferred out of the focus animation context.
- [ ] **macOS windowing**: a separate player window. New windows do not inherit the main
      scene's environment, so container and environment must be re-declared.
- [ ] **Image pipeline** *(surfaced)*. Thousands of channel logos need disk caching and
      downsampling, plus a memory purge on backgrounding to avoid jetsam.
- [ ] **Empty, loading and error states** that explain what to do next.
- [ ] **UI test target** *(surfaced)*. Needed to verify screens past the launch screen at all;
      `simctl` has no tap command.

---

## M5 — Sync

- [ ] **Enable CloudKit mirroring** *(asked for, as "iCloud sync")*. Needs a Developer Program
      team and a real container identifier first; without them the app fails to launch rather
      than degrading.
- [ ] **Favourites** across devices
- [ ] **Watch progress and resume points** across devices
- [ ] **App settings**, including the selected playback engine
- [ ] **Encrypted provider credentials** via `@Attribute(.allowsCloudEncryption)`
- [ ] **Reconcile guard**: never let an empty local catalog push mass deletions to CloudKit.

---

## M6 — IPTV depth

Features real users expect that the brief did not name. All *(surfaced)*.

- [ ] **EPG / TV guide UI**. A player without a guide is half an app.
- [ ] **Catch-up and timeshift**. Xtream supports it; the M3U attributes are already parsed.
- [ ] **Multiple playlists** and switching between them.
- [ ] **Profiles**. Shared family devices, especially Apple TV.
- [ ] **Parental controls**. A PIN cannot ride iCloud Keychain to tvOS, so it goes through the
      CloudKit container.
- [ ] **Subtitles**. LumeEngine returns plain text only, with no positioning or styling and no
      bitmap subtitle support, so rendering is Panop's job.
- [ ] **Audio and subtitle track selection** per engine.
- [ ] **Large-catalog hardening**. Indexes on every predicate and sort column, batched writes
      with autosave off, and background indexing that yields while the user browses.
- [ ] **Performance benchmarks** in a separate target and configuration. Never benchmark in
      Debug; `-Onone` makes parser numbers fiction.

---

## M7 — Release readiness

- [ ] App icon and marketing assets
- [ ] Localisation via String Catalogs
- [ ] `PrivacyInfo.xcprivacy` privacy manifest
- [ ] Log redaction audit. Credentials must never reach a log or a diagnostic export.
- [ ] tvOS archive validation. Some failures appear only at upload, never in a normal build.
- [ ] App Store listing and review notes. Player-only apps are legitimate, but the category
      draws scrutiny, so state clearly that Panop ships no content.

---

## Deferred, with reasons

| Item | Why it is deferred |
|---|---|
| **VPN auto-enable** | Not possible for a third-party tunnel on Apple platforms. Shipping our own needs a Network Extension and an organisation account (ADR 0006) |
| **Android UI** | Core stays portable, but no UI work planned. Swift 6.3's Android SDK makes this real later (ADR 0007) |
| **Windows / Linux UI** | Same. Core compiles there; no UI planned |
| **KSPlayer engine** | GPL-3.0. Adapter kept behind `PANOP_ENABLE_KSPLAYER`, dependency unlinked (ADR 0002) |
| **DRM** | IPTV streams are effectively never DRM protected |
| **Recording, Chromecast, multi-view** | Not in the brief. Revisit after M6 |

---

## Open decisions

Things needing a human answer before the milestone that depends on them.

- [ ] **Apple Developer Program team.** Blocks M5 entirely, and device builds generally.
- [ ] **Bundle identifier.** Currently `com.panop.Panop`, baked into entitlements.
- [ ] **Copyright holder name** in `LICENSE`, currently "Nico Kuhno".
- [ ] **Install the iOS and tvOS platforms** so those builds can be verified at all:
      `xcodebuild -downloadPlatform iOS` and `-downloadPlatform tvOS`.
- [ ] **Buy KSPlayer's LGPL licence?** Only if its Metal renderer proves worth it after M2.
- [ ] **Metadata enrichment** (TMDB artwork, ratings) and **scrobbling** (Trakt, Simkl). Both
      add real value and real scope. Not currently planned.
