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
- [x] **Group M3U episodes into series.** In M3U a `/series/` address is one *episode*, and a
      real playlist puts hundreds of thousands of them in the `.series` kind (86% of a real file
      by one measure), so the Series screen would have been a wall of episodes. At import, a name
      such as `Dark S01E05`, `Dark - s1e5 - Title`, `Dark.S01.E05`, `Dark 1x05` or `Dark Season 1
      Episode 5` is read by `EpisodeTitle` (one pass over the characters, no regular expression,
      since it runs on every series entry; names it cannot read, such as `Dune Part 2`, are left
      alone). The first episode of each show makes a **series entry** (named from the title,
      with the first episode's logo and position), and each episode is stored with its series,
      season and episode numbers. **Decision the roadmap left open: stored, not fetched lazily**,
      because an M3U has no per-series endpoint to fetch from; the cost is that an episode row
      is kept, but the Series screen asks only for shows (an index serves it) and a show's
      episodes are read when it is opened (a second index). A show whose episodes all leave the
      list goes with them, and re-importing is idempotent. A series entry that could not be
      grouped still plays by itself. 8 importer tests, 6 parser tests (a table of 15 spellings, 12
      names that must not match, and a speed check), 5 query tests on a real store, and UI tests
      on iOS and tvOS. **Not verified:** against a real playlist's naming (the parser is built
      from the common conventions; a provider with its own would need another form), and
      existing stores gain the new fields and indexes by lightweight migration, which was
      checked on new stores only.
- [x] **M3U channel order.** Each M3U entry is stored with its position in the file as its sort
      number (counting across kinds, not counting entries left out), and the channel list has a
      Sort control: By name (the default) or the provider's order, which for Xtream is the number
      the panel gives each channel. Served by two new indexes. **A decision the roadmap had the
      other way round:** it said to assign a position on insert only, so that a provider who
      reorders does not rewrite every row. That would leave a reordered list in its old order and
      put new channels at the end, which is not what anyone sorting by the provider's order
      wants. So the position follows the file, and, as for every field, only a row whose value
      changed is written: a reorder costs a rewrite of the rows that moved (measured earlier at
      about 8 s for a 2% change in 100,000), an unchanged file costs nothing (digest skip). Tested
      in the package (order follows the file, across kinds, follows a reorder, no gap where an
      unusable entry was) and against a real on-disk store, and by UI tests on iOS and tvOS.
      **Not verified:** that an existing store gains the two indexes cleanly; they were checked on
      new stores only (adding an index is a lightweight migration, but no old store was
      opened).
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
- [x] **Keep the guide window small.** *Already done, the entry was stale:* the sync keeps now-2h
      to +48h (`GuideWindow.standard`, tested in `PlaylistSyncTests`). Import time scales with rows kept, and most of a
      provider's 7-14 day guide is never viewed. A window of roughly now-2h to +48h keeps a
      400-channel guide near 40k rows (~5 s cold) instead of 200k+. Choose it in the sync
      service, not the importer.
- [x] **Show channels while the first import runs.** *Mostly already true, and measured.* Rows
      appear as soon as they are saved, because the list's query sees each background save, so
      the list fills in as the import goes; the screen says "Getting your channels…" only until
      the first rows land. The roadmap's worry was that every save re-runs the list's query on the
      main thread. Measured (Release, this Mac, `Scripts/test-app.sh --benchmark catalog`): an
      80,000-channel first import with a list refetching its first page after **every one of the
      403 saves** left the main thread's worst delay at **20 ms against 12 ms with nothing
      watching, with no gap over 50 ms** (a gap of three frames); the import itself took 21.2 s
      against 17.8 s, 19% longer from the contention. So no batching of the refresh was built.
      **Not measured:** an Apple TV HD, where that 20 ms could be several times larger; if a
      stall shows there, the fix is to coalesce the refresh while a sync runs. M3U is read in
      file order, so the first channels in the file appear first.
- [x] **M3U identity when stream URLs carry rotating tokens.** *Decided: the whole address stays
      the identity, query string included.* The roadmap asked to check real playlists before
      choosing, so one was checked (the iptv-org German list): 11 of about 245 addresses have a
      query, every parameter in them identifies the channel (`network_id`, `ref`, `profile`,
      `account`, `file`), and two entries differ only in `?network_id=16660` against `?network_id=535`.
      Stripping the query would have merged different channels. No rotating token appears in it.
      A test (`M3UIdentityTests`) keeps it that way. **If a real provider turns out to rotate
      a token**, the fix is to strip *named* parameters (`token`, `expires`, `sig` and the like),
      not the query as a whole, and it needs a sample of that provider's addresses first.
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
- [x] **Movies and Series** browsing, including episode lists *(asked for, VOD)*. Two tabs share
      one poster grid (`VODBrowseView`): searchable, paged like the channel list through the same
      bounded indexed fetch, posters through the image pipeline, a star and a progress bar on a
      card, the same long-press menu to star. A film plays on tap. A **provider series** is a
      shell, so opening it fetches its episodes then (`SeriesDetailView`: seasons in order with
      specials last, each episode with its length and how far through you are). An **M3U
      "series" entry** is already one episode with its own address, so it plays at once.
      Season grouping is in the portable package, tested on a real panel-shaped response. Looked
      at on iOS and Apple TV; UI tests cover the grid, resume and series on iOS, and the grids on
      tvOS. **Not verified:** the episode list against a real provider panel (no panel to
      test with), and M3U episodes are not grouped into series yet (the open item in M1).
      **Not done:** a detail page for a film (plot, cast, rating), and groups or categories.
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
      **Not done:** PiP and Now Playing, channel-switch latency against the other
      engines, and any real provider stream.
- [x] **Subtitle text from LumeEngine**. The engine hands back text and draws nothing, so
      `LumePlaybackEngine` looks the cue up against the playback clock ten times a second, only
      while subtitles are on, and `SubtitleOverlay` draws it above the controls. AVPlayer and
      libVLC draw their own, so `PlaybackEngine` is unchanged. Tested with a sidecar SRT on a
      playing stream (`loadExternalSubtitles`, which is also the hook for downloaded
      subtitles). **Not verified:** an embedded subtitle track in a real stream, and how it
      looks over real video. Plain text only, with no positioning or styling.
- [x] **Player overlay** shared across engines, built on `PlayerModel` so no engine needs its
      own: play and pause, a scrubber with ±10 s for video and a LIVE badge for channels, audio
      and subtitle menus, the engine name, and controls that hide four seconds after the first
      picture and stay up while paused or failed. The coordinator now forwards each engine's
      tracks and passes a track choice on. Tested through the model with a scripted engine;
      looked at on macOS through
      `PlayerSnapshot` (`TEST_RUNNER_PANOP_SNAPSHOT=1`, writes `/tmp/panop-player-*.png`) but
      **not on iOS or tvOS**, where tvOS shows a progress bar rather than a slider, since it has
      none. Subtitle menus list tracks, but no engine draws the text yet.
- [x] **Resume playback** from a stored position. Passed at load time (`PlaybackItem.startPosition`),
      never by seeking a running connection, which some providers cannot survive. The player
      reports progress every fifteen seconds and once more when it stops; nothing under ten
      seconds in is kept, and reaching the last 5% or last 30 seconds clears the point so the next
      play starts over. A film left part-way asks "Resume from 32:10" or "Start over" in the
      grids; Home's banner and cards resume without asking. Live channels never resume. Held
      in the cloud container with the favourites. 8 store tests, 4 for the throttling, and UI
      tests for resume and start over. Home now has a **Continue watching** rail
      of the films and episodes left part-way, the one watched last first, each card with a
      progress bar (`UserStateStore.continueWatching`, 2 tests). A film or episode seen to the
      end, or marked by hand in its context menu, shows a green check (`UserContentState.isWatched`,
      3 tests).

---

## M3 — Streaming performance

The brief called performance a key concept. For IPTV this concentrates in one number.

- [ ] **Fast channel zapping** *(asked for, as "streaming performance")*. Time from channel
      select to first frame is the metric users judge an IPTV app on. **Measured, not yet
      improved.** Release build, this Mac, a fresh engine per zap, median of 8 over the real
      network (`TEST_RUNNER_PANOP_LIVE_URL=... Scripts/test-app.sh --benchmark playback`):

      | Stream | AVPlayer | VLC | LumeEngine |
      |---|---|---|---|
      | 3sat, single-variant HLS | 276 ms | 132 ms | 715 ms |
      | ZDF, multivariant HLS | 148 ms | 81 ms | 2924 ms |
      | Local mp4 | 11 ms | 67 ms | 6 ms |
      | MPEG-TS over local HTTP | cannot read | 51 ms | 188 ms |

      What this says. (1) The default path is already quick: AVPlayer plays HLS in 150 to
      300 ms warm. (2) **LumeEngine is slow on multivariant HLS**, 2.9 s on ZDF, and tightening
      `probeSize` and `maxAnalyzeDuration` did not move it, so the cost is FFmpeg's HLS demuxer
      opening every variant, not probing. It only matters if Lume is the chosen engine, since
      AVPlayer takes HLS first by default. **Fixed**: Lume is now handed a playlist naming one
      variant plus its audio group (`HLSMultivariant`, `HLSVariantPicker`), 0.9 s against 3.2 s
      on ZDF (see docs/engines.md). (3) **Prefetching the playlist before the first zap** saved
      about 50 ms, inside the run-to-run noise, so it is not worth building. (4) The cold first
      zap is the larger gap (300 to 1000 ms against 150 ms), mostly DNS, TLS and a cold CDN.
      (5) Join times are not strictly comparable: libVLC reports `playing` when decoding
      starts, AVPlayer when its clock runs. **Not measured:** a raw MPEG-TS channel from a real
      provider, which is the case VLC and Lume exist for, and an Apple TV HD.
      **Levers, now closed.** *Remembering which engine worked for a channel* is built: when an
      engine other than the person's own choice ends up playing a channel, it is remembered
      (in the cloud container, with the favourites) and tried first next time, so a raw-TS
      channel AVPlayer cannot read stops failing there before it plays; the person's own choice
      playing it again clears the memory. Tested through the player model with a scripted
      factory (it is not even asked for the failing engine the second time). *A launch warm-up
      of libVLC and AVFoundation* was built and measured, and **rejected**: it saved about
      10 to 20 ms of VLC's 130 ms first zap (the rest happens when the engine first plays) and
      about 7 ms for Lume, while loading libVLC's plug-ins into memory for people who never use
      it, and memory is a budget on Apple TV. *A pre-created engine for the next zap* was not
      built: with the memory above, the only engine cost that mattered (VLC's creation) is paid
      only on a channel that needs VLC, and 50 ms there is not worth holding an engine and a
      surface in memory.
- [x] **Reconnect and backoff policy** on stall or IO error, distinguishing retryable failures
      from format rejections. In `PlaybackCoordinator` (see the M2 entry), driven by
      `PlaybackError.isRetryable`.
- [x] **Engine fallback on failure**, with the reason surfaced rather than a silent switch.
      Every fallback and reconnect carries a notice with its reason; the player shows it.
- [x] **Playback QoE metrics** *(surfaced)*: join time, rebuffer ratio, exits before first
      frame, engine fallbacks, reconnects and failures. A recorder in the portable core
      (`PlaybackSessionRecorder`) turns the coordinator's events into one record per viewing
      session, with the clock passed in so the arithmetic is tested exactly (14 tests: rebuffer
      time, paused time not counted, leaving before a picture, the first join time kept). The
      record is kept only when the session ends, never while it plays, by an actor that writes a
      JSON file in Application Support (last 300 sessions, a damaged file starts empty).
      **Nothing identifying is stored**: no address, channel name or account, which a test
      checks on the encoded record. Settings, Playback Statistics shows the typical and the
      slowest-tenth join time, the share of time spent waiting, sessions left before a picture,
      sessions that needed another player, sessions that failed, and the join time by engine.
      On this device only. **Not done:** sending any of it anywhere (nothing is, by design),
      and a per-channel view, which would need to store channel names.
- [ ] **Picture in Picture and AirPlay** via AVPlayer; note the other engines cannot match this. *Both wired, neither seen working.*
      PiP is wired for AVPlayer on iOS and macOS (a button in the controls, made from the video
      layer; tvOS has no PiP). Tested that it is offered once a layer exists and where the system
      supports it. **Not verified:** that the window actually floats and comes back, which needs
      a device. AirPlay is the system's route picker
      (`AVRoutePickerView`) in the controls on iOS and macOS, shown only while AVPlayer is the
      engine, since libVLC and LumeEngine cannot send video there; tvOS has no AirPlay out. Tested
      that it is offered for AVPlayer and not for the others. **Not verified:** a real AirPlay
      destination.
- [x] **Now Playing and remote commands**, needed for the Apple TV Siri remote. Title, position,
      length (or live) and play state go to the system's controls; play, pause, toggle, ±10 s
      and scrubbing come back from them, with scrubbing off for a live channel. Works for every
      engine because it hangs off `PlayerModel`. Tested through a recording stand-in and against
      the real `MPNowPlayingInfoCenter` on macOS, iOS and tvOS. **Not verified:** a real remote,
      the lock screen, or AirPods taps, which need a device.
- [ ] **Background audio**. `UIBackgroundModes` was *not* in fact set: the build setting for it
      produced nothing. It is now declared in `Config/Panop-Info.plist` and checked by a test, and
      the audio session is set to playback when a player starts. **Not verified:** that audio
      really continues with the app in the background, which needs a device.

---

## M4 — Interface

- [ ] **Modern UI pass** *(asked for)*. Home with rails, hero, artwork. **Home with rails is
      done**: a first tab with a Recently watched rail and a Favourites rail of channel cards
      (logo, name, a star when starred, the same star menu), a link to the full list, and empty
      states for no playlist and for nothing watched or starred yet. Each rail is a bounded
      fetch by entry id; an empty rail is not drawn. Looked at on iOS and Apple TV (a card style
      on tvOS, so a focused card lifts). UI tests cover the empty state and its Browse button on
      both, and, on iOS, starring, playing and finding both on Home. **Not done:** a hero for
      the channel last watched, artwork beyond logos, a rail per group or per source, and
      movie and series rails, which wait for those screens.
- [ ] **tvOS focus engine work** *(surfaced)*. Full-width focus targets, no `Color.accentColor`
      for fills, layout mutations deferred out of the focus animation context. **Audited and
      partly fixed:** no accent-colour fills anywhere; the remote-driven callbacks are deferred;
      the player controls now stay up while one has focus and count down once it lets go; and
      while they are hidden a focusable surface lets any direction press or Select bring them
      back (before, nothing on screen could take focus, so the remote could not wake them).
      **Now verified** by driving the real remote in the UI tests (`PanopUITests`): controls stay
      up while focused, Menu closes the player, and the player is reachable from the list.
      **Still open:** the controls coming back after they have hidden, by remote, since a held
      bar does not hide while it has focus and so that state is hard to reach.
- [x] **macOS windowing**: the player is a window of its own (`WindowGroup` with a value), not a
      sheet over the list. It can be moved, resized, put on another display and taken full
      screen, and opening the same item again brings its window forward. A new window does not
      inherit the main scene's environment, so the container and the services are declared
      again on it. **The window's value holds no stream address**: macOS saves a window's value
      to restore it, and an address can carry the account's login, so the value is only which
      item it is, and the window finds the address again, in the catalog for a channel or film
      and from the playlist's own login for an episode. Restoration is switched off, since a
      restored window would start a stream the moment the app opened. Closing the window stops
      playback and ends the session. **Verified on a real Mac**, by launching the app with a
      Debug flag that opens the window, clicking in it, and closing it: the window appeared
      with its controls, a click showed and hid them, and closing it left one window and one
      recorded session. 8 unit tests cover the request (no address, survives a save, the same
      item is the same window), the catalog lookup across playlists, and episode addresses.
      **Not covered by an automated UI test**: macOS UI tests need an accessibility grant given
      by hand; the check above is a manual one.
- [x] **Image pipeline** *(surfaced)*, `Panop/Services/Images/`, shown as `ChannelLogo` in the
      Live TV rows. Decodes with ImageIO at the displayed size (never the downloaded size); a
      memory cache with a byte budget (16 MB tvOS, 24 MB iOS, 64 MB Mac) emptied on a memory
      warning and on backgrounding; a disk cache in Caches capped at 120 MB, least recently
      used out first; one download per image however many rows ask; at most four in flight,
      newest first, so a fast scroll fetches what is on screen now; a download nobody waits for
      any more is cancelled; a failed logo is not asked for again for ten minutes; non-images
      and anything over 4 MB are refused and never cached. 17 tests with a scripted network.
      **Not measured:** scroll performance on a long list with real logos, and an Apple TV HD.
      **Not done:** logos for movies and series, and programme artwork.
- [x] **Favourites and recently watched** *(surfaced)*, on this device. Star a channel by
      touch and hold (or the remote's long press) or, off tvOS, a swipe; a star shows on the row;
      the list filters to All, Favourites or Recently watched (a toolbar menu, and a row at the top
      of the list on Apple TV, which shows no toolbar). Opening a channel records it. Held in
      the cloud container (`UserStateStore`, explicit fetches, never `@Query`), keyed by playlist
      *and* entry because Xtream stream ids repeat across providers. An unstarred channel with no
      history leaves no row; played-only rows are capped at 200; deleting a playlist deletes
      its favourites and history. 15 store tests, and UI tests on iOS and tvOS. **Not done:**
      the same for movies and series (no screens yet), resume positions (the field exists, nothing
      writes it), and a home screen that shows these as rails.
- [x] **Empty, loading and error states** that explain what to do next, for Live TV. The screen
      now tells apart: no playlist yet, a search with no match, still loading, **a source that
      failed (with the reason and a Try again button)**, and a source that loaded with no live
      channels. A failed source used to read "no channels". With channels showing, a banner names
      a source that could not be updated and offers the retry. Search is offered only once a
      playlist exists. Decision logic tested separately (`LiveEmptyState`); looked at on macOS
      and tvOS. **Not done:** the same for movies and series, which have no screen yet.
- [x] **UI test target** *(surfaced)*: `PanopUITests`, run with `Scripts/test-ui.sh [ios|tvos]`.
      iOS is driven by taps and tvOS by the real remote (`XCUIRemote`), against a deterministic
      app (`-panop-uitest`, Debug only). The suite (19 tests on iOS, 10 on tvOS) covers: the seeded channels,
      search, opening a channel, the controls and LIVE badge, pause and play, close, the controls
      hiding and a tap bringing them back, and on tvOS the controls **staying up while the
      remote has focus on them** and Menu closing the player. **Found three real bugs:** a row
      that ignored a tap in its empty middle (the whole row is now the target, which Apple TV
      focus also needs), hidden controls that a tap could not bring back (the gesture now has a
      layer of its own), and a focused Pause button covering the LIVE badge on Apple TV. **Not
      covered:** macOS (needs an accessibility grant), the Add Playlist flow, Settings, and
      playback itself, since the test engine draws no picture.

---

## M5 — Sync

- [ ] **Enable CloudKit mirroring** *(asked for, as "iCloud sync")*. Needs a Developer Program
      team and a real container identifier first; without them the app fails to launch rather
      than degrading.
- [ ] **Favourites** across devices. They exist on one device now (see M4, *Favourites and
      recently watched*) and live in the cloud container, so turning CloudKit on is what carries
      them across: no change to the model should be needed beyond the entitlement.
- [ ] **Watch progress and resume points** across devices. They exist on one device now (see M2, *Resume playback*), in the cloud container, so CloudKit carries them once it is on.
- [ ] **App settings**, including the selected playback engine
- [ ] **Encrypted provider credentials** via `@Attribute(.allowsCloudEncryption)`
- [ ] **Reconcile guard**: never let an empty local catalog push mass deletions to CloudKit.

---

## M6 — IPTV depth

Features real users expect that the brief did not name. All *(surfaced)*.

- [ ] **EPG / TV guide UI**. A player without a guide is half an app.
- [ ] **Catch-up and timeshift**. Xtream supports it; the M3U attributes are already parsed.
- [x] **Multiple playlists** and switching between them. Several sources can be added, and Live TV shows all of them or one chosen source (M2); each can be refreshed or deleted from Playlists.
- [ ] **Profiles**. Shared family devices, especially Apple TV.
- [ ] **Parental controls**. A PIN cannot ride iCloud Keychain to tvOS, so it goes through the
      CloudKit container.
- [ ] **Subtitles**. Plain text from LumeEngine is drawn now (M2); what is left is styling, positioning and bitmap subtitles. LumeEngine returns plain text only, with no positioning or styling and no
      bitmap subtitle support, so rendering is Panop's job.
- [x] **Audio and subtitle track selection** per engine. The player's controls list the tracks any engine reports and pass a choice to it (M2, *Player overlay*). Not yet checked against a real stream with several tracks.
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
