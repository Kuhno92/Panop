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

- [x] **`PanopXtream`** *(asked for)*. Client behind `HTTPTransport`, covering
      `get_live_streams`, `get_vod_streams`, `get_series`, `get_series_info`, `get_short_epg`,
      and the stream URL builders. Tests use a stub transport, no network.
      Big lists come back as pull-based batches (`XtreamBatches`) so a slow database write
      slows the download. A truncated body throws `truncatedResponse`; the reconciler must
      treat that as a failed import and never prune against it. Not yet verified: the
      `URLSessionTransport` against a real panel, and the off-Apple transport branch (CI only).
- [x] **`PanopEPG`** *(surfaced)*. XMLTV pull parser emitting batches, gzip support, and a
      rolling window rather than the whole guide. Guides exceed 100 MB.
      Own chunk-fed tokenizer rather than `XMLParser` (push-only, so no backpressure, and a
      separate module off-Apple). `GzipDecoder` lives in `PanopCore`, verified against zlib
      output at 1-byte chunks, and checks each member's CRC. A guide that never reaches
      `</tv>` throws `truncated`, same rule as Xtream: never prune against it.
      Measured in an optimized build on a generated 311 MB / 600,000-programme guide: XMLTV
      parses at ~80 MB/s (~155k programmes/s, so ~1.3 s for a typical 100 MB guide) and gzip
      decodes at ~165 MB/s. Profiling found two cheap wins (ASCII fast path for string
      conversion, no grapheme walk in the length cap), worth 1.7x. Not yet verified: the
      whole guide reader against a real provider, and the off-Apple branch (CI only).
- [x] **`PanopCatalog`** *(surfaced)*. Import and reconcile orchestration behind `CatalogStore`,
      so Android can reuse it later. M3U (remote or file), Xtream and XMLTV imports, with an
      in-memory reference store that the tests run against.
      **The rule:** a row is removed only after an import that ran to completion, and only if
      the removal is believable. No stamping of rows with an import generation, because that
      would rewrite every row on every unchanged refresh. Instead the importer keeps a set of
      64-bit id hashes (a few MB for 100k rows) and sweeps stored ids not in it; a hash
      collision keeps a stale row and can never delete a live one. A sweep that would remove
      more than half a catalog (and more than 25 rows) is held back as a `DeferredRemoval`,
      because an M3U file has no end marker and a cut-off download is indistinguishable from
      a smaller playlist. Confirming is refused if a newer import has run since.
      Xtream sections (live, movies, series) succeed or fail independently; a failed section
      removes nothing. M3U identity is a hash of the stream URL, never the group, so
      regrouping does not orphan favourites. Unchanged M3U files are skipped by digest.
      Not yet verified: import speed against a real store (the in-memory one sorts on every
      page and says nothing about throughput). That belongs with `SwiftDataCatalogStore`.
- [ ] **Group M3U episodes into series.** In M3U, a `/series/` URL is an *episode*, so a large
      playlist puts hundreds of thousands of episodes into the `.series` kind (Lume measured
      86% of a real file). Needs episode-name parsing (`S01E05`) to build series shells, and a
      decision on whether episodes are stored or fetched lazily as they are for Xtream.
- [ ] **M3U channel order.** Playlist order is not stored. Assign a position on insert only, so
      a provider that reorders does not rewrite every row.
- [x] **`SwiftDataCatalogStore`** in the app target, implementing that protocol. A `ModelActor`
      with autosave off; unchanged rows are never dirtied, so an unchanged batch saves nothing.
      Tests run against real on-disk SQLite (an in-memory store hides collation and paging
      bugs) and pass on macOS, iOS and tvOS. `Scripts/test-app.sh`.
      **Measured** (Release, this Mac, `Scripts/test-app.sh --benchmark`; ratios travel, seconds
      do not, and an Apple TV HD will be several times slower):

      | 100,000 entries | Time |
      |---|---|
      | Cold import | 17.8 s (~5.6k rows/s) |
      | Refresh, file unchanged (digest skip) | 0.06 s |
      | Forced refresh, nothing changed | 5.0 s |
      | Refresh, 2% changed and 3% removed | 7.6 s |
      | Count entries of a kind | 0.01 s |

      | 200,000 programmes | Time |
      |---|---|
      | Cold guide import | ~26 s |
      | Guide refresh, nothing changed | ~7.8 s |
      | Window moved on 20% (40k expired, 40k new) | ~14 s |
      | Every programme edited | ~115 s (updates cost ~3x an insert) |

      What the tuning found: saving in slices of 200 rows beats 1,000 by ~25% and 5,000 by
      2.7x (save cost is superlinear in batch size); a composite `#Unique` cost ~35% on bulk
      insert and guarded nothing the single-writer actor does not already rule out, so the big
      tables use plain indexes and a test asserts no duplicates; dropping the per-kind index
      made every refresh slower than it made the first import faster, so it stays. A guide
      that paged every programme key with a compound cursor took 47 s (an invisible scan);
      the sweep now reads per channel. See the follow-ups below.
- [ ] **Keep the guide window small.** Import time scales with rows kept, and most of a
      provider's 7-14 day guide is never viewed. A window of roughly now-2h to +48h keeps a
      400-channel guide near 40k rows (~5 s cold) instead of 200k+. Choose it in the sync
      service, not the importer.
- [ ] **Show channels while the first import runs.** A cold import is minutes on an Apple TV.
      Import live first and let the list fill in, but note every background save re-runs the
      main context's `@Query`s, so batch the UI refresh instead of updating per save.
- [ ] **M3U identity when stream URLs carry rotating tokens.** Identity is a hash of the whole
      URL. A provider that adds a per-request token to each URL makes every row look new and
      every old row look stale, which the removal gate then (correctly) holds back, but
      favourites would still be orphaned. Needs a decision on which query parameters to strip
      before hashing. Check real playlists before choosing.
- [x] **Playlist import flow**: add a playlist by URL, file, or Xtream credentials. Xtream logins
      are checked against the panel before anything is stored, so a typo fails at the form. The
      playlist record (cloud container) holds only a display host; the whole source URL counts as a
      secret because M3U links usually embed the login. `CatalogImporter.sync` imports the catalog
      then the guide, and a broken guide never fails or undoes the catalog. Playlists refresh
      themselves at launch when older than 12 hours. The screens launch (checked on macOS) but no
      UI test has driven them, so the add form, the swipe/context actions and the "review missing
      items" prompt are unexercised by a person or a test.
      **Managing sources:** each row has a visible actions menu (Refresh, Re-import Everything,
      Stop Updating while running, Delete), the same actions on right-click and swipe, and a
      Refresh All button. Delete removes the catalog rows first and touches the login and record
      only once that succeeded, so a failure leaves a retryable playlist instead of orphaned
      channels; it works while a sync is running. A refresh that cannot run (missing login) says
      so on the row. Measured: deleting 30k channels 0.22 s, 77k channels 0.78 s, off the main
      thread. Checked by rendering the rows in a real window; the swipe and right-click paths
      and the confirmation dialogs have not been driven by hand.
- [x] **Incremental re-import**. Skip unchanged playlists by digest rather than reparsing 80,000
      entries every launch.
- [x] **Credential storage in Keychain**, with `kSecUseDataProtectionKeychain` for macOS parity.
      Falls back to the file-based keychain when the entitlement is missing, as it is in every
      locally signed dev build. Worth knowing: without the entitlement, *reads* report "not found"
      rather than "missing entitlement", so reads and deletes must fall back on not-found too.
      Items are `AfterFirstUnlockThisDeviceOnly`: background refresh needs them while locked, and
      cross-device credentials belong to the CloudKit container (M5), not iCloud Keychain.

> Watch out: iCloud Keychain does not sync to tvOS. Anything that must reach an Apple TV goes
> through the CloudKit container instead.

---

## M2 — Browse and play

The first milestone where Panop is usable.

- [ ] **Live TV list** with provider groups *(asked for)*. **Partly done:** Live TV shows the
      channels of every source, or one chosen source (remembered, and offered only when there
      are several), sorted by name, with search and a page that grows as you scroll up to a
      5,000 row cap. Still to do: filtering by the provider's group. An earlier placeholder took
      the first 200 rows it found, which showed only the first playlist's channels.
      Names sort on a stored `nameKey` (case and accents folded at import) because SwiftData's
      default string sort is localised and no index can serve it. Measured on 107k channels
      across two sources: first page 0.01 s, grown to the cap 0.12 s, search 0.03 s. The two
      browse indexes cost about 5 to 8% on import.
- [ ] **Movies and Series** browsing, including episode lists *(asked for, VOD)*
- [ ] **Search** across the catalog. Needs SQLite FTS or bounded predicates with a fetch limit;
      an unbounded sort defeats the limit entirely.
- [x] **Engine coordinator** *(surfaced)*: owns the ordered fallback list, reconnect and
      backoff. Never inside an adapter (ADR 0002). Portable (`PanopPlayback`), tested with a
      scripted fake engine in 0.2 s. A format rejection moves to the next engine without a retry;
      a recoverable failure retries on a *fresh* engine with backoff; load, first frame and
      stalls all have timeouts, because a stream that neither plays nor fails is otherwise
      invisible; a reconnect budget refills after stable playback; VOD resumes where it stopped;
      every fallback carries its reason; a superseded session (fast zapping) cannot disturb the
      new one. The item is chosen per engine (HLS for AVPlayer, raw `.ts` for the others).
- [x] **AVPlayer adapter**. First real engine. Reports only; no retry or fallback. Tested against
      real AVFoundation on macOS, iOS and tvOS, including real H.264 video reaching the layer.
      **Measured:** AVFoundation reports an unreadable stream with a different code per
      container (-11829 malformed MP4, -11828 MKV, an *unnamed* -11849 for MP3 and transport
      streams), so a list of known codes is always one behind. The adapter therefore maps any
      AVFoundation error that is not clearly network, authorization or decode to
      `unsupportedFormat` (next engine, no retry). A garbage `.m3u8` never fails at all: the item
      stays "unknown" forever, which is why the coordinator's timeouts are not optional.
      Floor for zapping, no network, warm: ~4 ms to first frame (cold ~80 ms). Not yet verified:
      any real provider stream. **Practical limit today:** AVPlayer cannot read raw MPEG-TS, so
      most M3U live streams fail until VLCKit or LumeEngine exists; Xtream live works (HLS).
- [x] **VLCKit adapter**. LGPL, must stay dynamically linked (verified: `@rpath/VLCKit.framework`,
      no libvlc symbols in the app binary). Pinned to **4.0.0-a24**, an alpha and the only
      SwiftPM line. Reports only, like the AVPlayer adapter. **Verified on real bytes:** a raw
      MPEG-TS stream muxed by libVLC itself and served over HTTP the way a provider serves live
      TV; AVPlayer refuses it and the coordinator moves to VLC, which plays it. Also verified:
      play, pause, seek, resume, stop, garbage and missing files reported as failures, a healthy
      stream settling at `playing` and not being reconnected, and real video surviving its
      surface leaving the screen. Tests pass on macOS, iOS and tvOS simulators; the app links
      for real iOS and tvOS devices (unsigned). **Not verified:** any real provider stream, and
      the screens by eye. Crashes found and fixed on the way, all recorded in `docs/engines.md`:
      rendering into a detached view, releasing a player on the main thread, a delegate class
      inheriting main-actor isolation, and a 0 to 100 versus 0 to 1 buffering mix-up.
- [x] **LumeEngine adapter**, vendored as a pinned submodule (`v0.2.2`), never a URL dependency.
      Built on `PlayerSession`, which is public after all, so the adapter has the typed event
      stream and a start position set at open time. Plays raw MPEG-TS over HTTP and, checked by
      hand, the 3sat and ZDF HLS streams (3sat joins in 0.75 s, ZDF in 3.2 s). Its own HTTP
      reconnect is switched off: that policy is the coordinator's. Tests on macOS, iOS and tvOS.
      **Not done:** subtitle text drawing (the engine returns cues,
      nothing shows them yet), PiP and Now Playing, channel-switch latency against the other
      engines, and any real provider stream.
- [ ] **Subtitle cues from LumeEngine**: `session.subtitles.activeCues(at:)` has the text, and
      `PlaybackEngine` has no channel for it yet.
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
- [ ] **UI test target** *(surfaced)*. The only reliable way to verify screens past launch on
      iOS. tvOS can be driven by synthetic keystrokes; iOS cannot be tapped from the CLI.

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
