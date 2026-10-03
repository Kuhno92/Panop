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

- [x] **Live TV list** with provider groups *(asked for)*. **Partly done:** Live TV shows the
      channels of every source, or one chosen source (remembered, and offered only when there
      are several), sorted by name, with search and a page that grows as you scroll up to a
      5,000 row cap. Filtering by the provider's group is done (the Category button, M2). An earlier placeholder took
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
      test with). M3U episodes are grouped into series (see M1).
      A film has a **detail page**: poster, title, a line of year,
      genre, length and rating, the plot, director, cast and country, and Play, Resume from,
      Start over, favourite and watched. What the catalog holds shows at once; a provider
      panel's extra details (`get_vod_info`, lenient decoding, 6 tests) are fetched when the
      page opens. An M3U source has nothing more to fetch. UI tests on iOS (page, resume and
      start over through it). Live TV, Movies and Series have a **Category** button that
      opens a searchable list of the source's categories (read from the small category table,
      one entry per name across sources) and narrows the list to one, together with source,
      search and sort, through the same bounded fetch (two new indexes on kind, category and
      name or provider order; 5 query tests, UI tests on iOS). **Not verified:** that an
      existing store gains those two indexes cleanly. **Not done:** a backdrop image, a
      trailer, and counts next to the category names.
- [x] **Search** across the catalog. Home has a search field; typing replaces its rails with
      matches for live channels, movies and series together (12 per kind, none drawn when a kind
      has no match), each the same bounded, indexed fetch its own screen uses, 250 ms after typing
      stops. Tapping plays a channel, opens a film's page, or opens a series. UI tests on iOS.
      It is on Home rather than a tab of its own because an iPhone shows five tabs, and a sixth
      pushed Settings into "More". **Not done:** matching on more than the name (plot, cast), and
      ranking: results are in name order.
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
      Now Playing and PiP are wired for the player (see M4), and
      channel-switch latency against the other engines is measured (M3). **Not done:** any real
      provider stream.
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

- [x] **Lists stay smooth against a real provider** *(asked for)*. Measured on a real panel (1,026
      channels, 10,425 movies, 1,394 series, a 38 MB guide, 56,000 programmes), in an optimised
      build, which found two main-thread costs: the "Now:" line on each channel row read the
      guide with a query that could not use the index, **25 ms a row**, now two index reads at
      **0.2 to 0.5 ms**; and the lists re-read their whole result each time they grew
      (**18 ms** from 300 rows to 600, **31 ms** from 600 to 1,200, mid-scroll). Lists are now fed
      by `CatalogListModel`: pages of 60 then 120 rows read on a background context
      (`CatalogReader`), handed over as plain `CatalogRow` values and appended; the catalog's
      changes are followed with a debounced background re-read. The longest main-thread wait
      while paging through all 1,026 channels is **3.3 ms**. The default order is now the
      **provider's own** on Live TV, Movies and Series (the panel's `num`, now read for series
      too); "By name" is one choice in Sort. `RealProviderBenchmarks` repeats the measurements
      against any provider (login from the environment only, never stored).
      Then nothing slow is left on the main thread while rows appear: the "Now:" line reads an
      in-memory cache (`GuideNowStore`) filled by one background read for the rows on screen
      (rows that scroll away first are never read), and a logo or poster already in memory is
      drawn in the row's first frame (`ImagePipeline.cachedImage`) instead of a placeholder and
      then the image. **Not measured:** tab switching and scrolling on a real display; an
      attempt to host the screens in a hidden window never laid out rows, so its numbers were
      discarded. Debug builds are several times slower than Release and are not a fair judge.
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
      both, and, on iOS, starring, playing and finding both on Home. The "Continue watching" banner is now a **hero**, its
      artwork enlarged and softened behind it (`BackdropView`), and a film's page shows the
      panel's backdrop when it has one. **Not verified by eye:** how either looks on a real
      screen; the UI tests only show nothing broke. **Not done:** artwork beyond what the
      catalog holds (channels have only logos, so their hero is a tint of the logo), a rail
      per group or per source, and movie and series rails.
- [x] **Live-only sources: make VOD optional** *(asked for)*. The add form has a "Live TV only"
      switch. Such a source skips the movie and series part of the import: an Xtream panel is
      never asked for them (two of three large downloads saved), and an M3U file is still read
      through but none of its films or episodes is stored, nor counted as unusable. With no
      source that has VOD, the Movies and Series tabs are not shown (and Home is selected if one
      was open); with no source at all they stay, since there is nothing to hide yet. The
      playlist row says "Live TV only". Package tests for both importers and the descriptor,
      app tests for the library, UI tests on iOS and tvOS (tabs hidden, and present for a full
      source). An existing source can be switched
      from its menu ("Live TV Only" and "Include Movies and Series"): off removes the stored
      movies, series and their categories (not through the sweep, so the mass-removal check
      does not hold it back), on forces a full re-import. 2 package tests and 1 app test.
- [x] **Startup behaviour** *(asked for)*. Settings has "When Panop opens": Home, Live TV, Movies,
      Series, or Play a channel, which adds a searchable picker for the channel. The screen is
      known from the settings alone so the first frame is the right one; a channel starts from
      the catalog already on disk (no wait for a sync), and one that has since gone leaves Live
      TV showing. Movies and Series are not offered, and fall back to Home, when no source has
      them. 7 tests for the plan and the lookup, and a UI test on iOS for choosing the channel.
      **Not verified:** the channel actually starting at launch (UI tests choose their own
      screen and skip it, since the playlist id is random), by hand on a device.
- [x] **Categories as chips, with editing** *(asked for)*. Live TV, Movies and Series show the
      provider's categories as a row of chips, in the order the provider lists them (a category's
      position is stored at import: the panel's list order, or an M3U file's first appearance).
      Two buttons pinned beside the chips (outside the scrolling row, so always in view) open the
      searchable list (past 12 categories) and an **editor** where each category can be moved
      up or down or hidden, with a reset to the provider's order. A hidden category's chip and
      its entries leave the lists, favourites, recents and search. The choices are per kind and
      name, kept in the person's own state (`CategoryPreference`). Unit tests for the rules,
      persistence and paging past hidden categories; UI tests on iOS for hiding and moving.
      **Not verified on a Mac by eye:** the editor sheet (an explicit size is set for it there).
- [x] **Provider dividers and hiding a channel** *(asked for)*. Providers put heading entries
      in their channel lists, such as `##### DE SPORTS #####`. Nothing but the name tells them
      apart (every other field of one matched a real channel's, on a real provider), so an entry
      whose name is fenced by three or more of the same decoration character at both ends
      (`#`, `=`, `-`, `*`, `★`...) is not imported. A provider that decorates differently is
      not recognised, so any channel, film or series can also be **hidden by hand** from its
      menu and shown again from Settings, Hidden; hidden entries stay out of every list and
      search, and keep their favourite, history and resume point.
- [x] **Movies and Series by category, with source and sort** *(asked for)*. With every category
      selected the screens show the first category's titles under its heading, then the second's,
      and so on, in the order the categories are arranged (the person's, else the provider's),
      with the entries that have no category last under "Other"; a chosen category is just its own
      titles under its heading, and headings stay pinned while scrolling (not on Apple TV).
      The sort applies within each category: provider's order, recently added, by name, top rated
      (two more indexes). A source menu appears with several sources that have films; both
      choices are remembered. A large first category does not hold up the first screen: the
      read fills across categories until it has enough rows (`CategorySectionsModel`, one
      background call per read). 8 model tests, UI tests on iOS and tvOS. **Not seen on a
      display by eye.** **Not done:** a collapsed rail per category as an overview, and per-title
      rating on the poster.
- [x] **Controls stay up behind an open menu** *(reported)*. The player's controls hid after a few
      seconds with the AirPlay picker, or the audio or subtitle choice, open on top of them,
      taking it away. Holds now have a reason (focus, `airplay`, `audio`, `subtitles`), and the bar
      comes down only when none is left. AirPlay reports the route picker opening and closing
      through its delegate; on iOS and macOS the audio and subtitle choices are popovers with
      known state, because a SwiftUI `Menu` cannot say when it is open (Apple TV keeps its menus,
      held by focus). 3 unit tests and an iOS UI test (menu open past twice the timeout). **Not
      verified:** the AirPlay picker itself, which is a system dialog no test can open.
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

- [x] **Discovery rails** *(asked for)*: Netflix-style rails built only from the person's own
      library. Trending, because you watched, new releases, top rated, genre, franchise, classics,
      decades, a pick of the day and what was watched most; on Home, and at the top of Movies and
      Series. The provider's own year, rating, genre, cast, TMDB id and adult flag feed them; adult
      titles are never suggested. Computed off the main thread, cached on disk, rebuilt after a
      change. A Settings switch turns them off and "Forget what I watched" clears the history they
      learn from. **Not done:** running the build against the real 10,000-title library to time it
      and measure memory (the benchmark needs the provider login in the environment), UI tests of
      the rails (the seeded test library has no films), and "Next up" and rating-based seeds from Simkl.
- [x] **Simkl** *(asked for)*: public trending list (named as Simkl's, with a link to each title),
      sign-in by code and QR code, finished films and episodes recorded on the account in batches
      that survive being offline, and the person's plan-to-watch list as a rail. **Dormant until the
      app is registered at Simkl and `SimklConfig.clientID` is set.** Unit-tested against stubs
      only: the list response shape, the sign-in and the history call have not met the live API.
      Free below $150 a month of revenue, a licence above (see THIRD-PARTY-NOTICES.md); all of it is
      in `PanopSimkl`, which can be dropped.

---

## M5 — Sync

- [ ] **Enable CloudKit mirroring** *(asked for, as "iCloud sync")* (ADR 0009). **Built, not yet run against
      iCloud.** The entitlements (`Config/Panop.entitlements`: CloudKit and the container
      `iCloud.com.panop.Panop`, push) are in the project, mirroring is chosen at launch from facts
      (`CloudSync.decide`: the switch, the entitlement, an account, not a test) and falls back to a local
      store with the reason shown, and **Settings has an iCloud section** (a switch, a switch for logins, a
      plain status). **Blocked on one step that needs Xcode's own account:** build once in Xcode so it
      registers the App ID `com.panop.Panop` and the container on team 4HUJUM5AUG (a command-line build
      reports "No Accounts"). Then `TEST_RUNNER_PANOP_TEST_CLOUDKIT=1` runs a test that opens the real
      mirrored store, and two devices are needed to see data travel.
- [x] **Playlists across devices**: they sync with the state, so a favourite names a playlist both devices
      have. A playlist removed on another device is removed here (channels, login, state), on a finished
      CloudKit import only. One that arrives is fetched if its login is there. Tested against the stores.
- [ ] **Favourites** across devices. They live in the cloud container, so turning CloudKit on carries them;
      verified against the stores, **not against two devices**.
- [ ] **Watch progress and resume points** across devices. Same: in the cloud container, not seen travelling.
- [ ] **App settings**, including the selected playback engine. Not done: they are in the device's
      preferences, which do not sync; the cloud container would need a settings record.
- [x] **Encrypted provider credentials** via `@Attribute(.allowsCloudEncryption)`: a playlist's login travels
      on its record, encrypted by CloudKit, as a switch that is on by default. The decision logic (upload,
      adopt on a second device, withdraw, a conflict) is tested. **Not seen across two devices.**
- [x] **Reconcile guard**: other devices' changes are applied on a finished, successful CloudKit import
      only, never because a record is missing from the local store, so an empty or reset store cannot
      remove anything.

---

## M6 — IPTV depth

Features real users expect that the brief did not name. All *(surfaced)*.

- [x] **EPG / TV guide UI** *(asked for)*. A Live TV row says what is on now **and what comes next**
      (two lines that change as the hour turns, read again once an answer has run out). Its menu has
      "Programme Guide", one channel's schedule, with a Watch button. And **TV Guide** (a button in the
      Live TV toolbar, the first row on Apple TV) opens a **time grid for the channels of the current
      list**: the same source, category, search and favourites as the list, a channel down the side that
      stays in view, time along the top that stays in view, each programme as wide as it is long, a red
      line for now, what is on highlighted with its progress, and what is coming up beside it for the next
      ten hours. Tapping a programme opens it in full with a way to watch the channel; tapping a channel
      plays it. Channels are read as they scroll into view, in batches, off the main thread, one bounded read
      each on the (source, channel, start) index. A programme's title stays clear of the channel column
      while its start is scrolled under it. On Apple TV the grid takes the whole screen and Menu closes it.
      Tested: the layout arithmetic, the batching model, the lookups, UI tests on iOS and tvOS (the grid,
      a programme's details, playing from it, the next line, and the channel schedule from the row menu on
      Apple TV). **Not done:** a day picker (the grid shows from an hour ago to ten hours ahead), jumping to
      a time, a filter for channels that have a guide, and a reminder or record action. **Not seen on a
      real Apple TV or with a real provider's guide.**
- [ ] **Catch-up and timeshift**. Xtream supports it; the M3U attributes are already parsed.
      **Catch-up for Xtream is built**: a channel the panel archives (`tv_archive`) lists the
      programmes that aired within its window under "Earlier" in its guide, and tapping one plays
      it from the start through the panel's timeshift address (`XtreamClient.catchupURL`, written
      in the panel's time zone, read from the login answer). The aired programme travels as a
      `CatchupWindow` (no address, no login) so a Mac player window can rebuild it. 4 package
      tests, 5 app tests. **Not verified:** against a real panel, in particular that its archive
      honours the advertised time zone. **Not done:** seeking (played as a stream with no
      scrubber), M3U catch-up (`catchup-source` templates differ per provider), and timeshift
      (pausing and rewinding live).
- [x] **Multiple playlists** and switching between them. Several sources can be added, and Live TV shows all of them or one chosen source (M2); each can be refreshed or deleted from Playlists.
- [x] **Profiles** *(first part)*: up to eight, each with its own favourites, history, hidden titles,
      category choices, suggestions and adult filter. Added, renamed and deleted in Settings → Profiles,
      switched there or from a menu on Home (iOS, macOS; Apple TV through Settings). A new profile starts
      with adult content hidden; with a PIN set, switching to a profile that shows it, and deleting one,
      ask for the PIN. The first profile owns everything saved before. Tested on iOS by a UI test.
      **Not done:** a "who is watching" screen at launch, avatars, syncing profiles between devices (the
      list lives in this device's defaults, the rows in the cloud container), and per-profile Simkl
      accounts (one Simkl account is shared by all profiles on a device).
- [x] **Hide adult content** *(surfaced)*: a Settings switch, on by default, leaves categories a provider names as adult out of the lists, search and suggestions. A category the person hid themselves stays their own choice. **Not done:** a PIN to turn it off, which is the parental-controls item below.
- [x] **Parental controls** *(first part)*: a 4 to 6 digit PIN, stored as a salted hash in this
      device's Keychain, that guards turning the adult filter off and changing or removing the PIN.
      Five wrong tries lock it for a minute, doubling to a quarter of an hour, and the count survives
      quitting. Tested on iOS by a UI test. **Not done:** syncing the PIN to other devices (it cannot
      ride iCloud Keychain to tvOS, so it goes through the CloudKit container, which is not enabled),
      per-profile PINs, and locking other things behind it (a rating limit, specific categories).
- [x] **Subtitles** *(styling done)*. Settings → Playback → Subtitles sets size, colour, background and a raised position, with a preview. Panop's own overlay (Lume) uses it at once, and AVPlayer gets it as text style rules once the style is changed, so the system caption setting stays in charge until then. **Not done:** VLC, which draws its own subtitles and has no hook for this, and bitmap subtitles. Plain text from LumeEngine is drawn now (M2); what is left is positioning and bitmap subtitles. LumeEngine returns plain text only, with no positioning or styling and no
      bitmap subtitle support, so rendering is Panop's job.
- [x] **Audio and subtitle track selection** per engine. The player's controls list the tracks any engine reports and pass a choice to it (M2, *Player overlay*). Not yet checked against a real stream with several tracks.
- [ ] **Large-catalog hardening**. Indexes on every predicate and sort column, batched writes
      with autosave off, and background indexing that yields while the user browses.
- [ ] **Performance benchmarks** in a separate target and configuration. Never benchmark in
      Debug; `-Onone` makes parser numbers fiction.

---

## M7 — Release readiness

- [x] App icon *(done)*: an eye, for Argus Panoptes the all-seeing giant: a glassy eye with a glowing iris, a play triangle for a pupil, a ring of small dots for his hundred eyes, and rings spreading out like a broadcast (and like the eyes of a peacock tail). A plainer outline version stays available (`PANOP_ICON_STYLE=classic`). Drawn in code (`Scripts/icon/main.swift`), rendered for iPhone and iPad, Mac, and Apple TV (layered, with Top Shelf images) by `Scripts/make-app-icon.sh` into `Panop/Assets.xcassets`. Checked by looking at it at 1024 and 120 px and by the asset compiler; **not yet seen on a home screen or in the Dock.** No dark or tinted iOS variants yet.
- [ ] Marketing assets: screenshots and the App Store listing
- [x] Localisation via String Catalogs: `Panop/Localizable.xcstrings` with English and German (322 strings), covering the screens, the player and the messages built in code. A UI test launches the app in German and checks the tabs, Settings and a name built in code. `Scripts/check-localisation.sh --strict` lists strings with no entry or no German. **Not done:** other languages, the app's name and permission texts (`InfoPlist.strings`), plural forms beyond one entry, and VLC's own on-screen texts.
- [x] `PrivacyInfo.xcprivacy` privacy manifest: no tracking, no collected data, and the two
      required-reason APIs the app uses (UserDefaults `CA92.1`, file timestamps `C617.1`, for the
      image cache). Checked to ship in the built app. **Not checked:** the manifests of the
      linked frameworks (VLCKit, LumeEngine), which a store upload validates separately.
- [x] Log redaction audit. Credentials must never reach a log or a diagnostic export. **Audited**:
      the app and the package make no logging call at all (and a lint rule, `no_logging`, now
      fails the build on a new one); import errors are scrubbed of the account's login at their
      source (Xtream, M3U download, guide); engine error text never reaches the screen, which
      shows fixed wording by error code; the playback statistics file holds no addresses or
      names. **Not covered:** any logging inside the vendored engines (libVLC, FFmpeg), and
      a diagnostic export, which does not exist yet.
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
- [x] **Install the iOS and tvOS platforms** so those builds can be verified at all (both installed, all test scripts run):
      `xcodebuild -downloadPlatform iOS` and `-downloadPlatform tvOS`.
- [ ] **Buy KSPlayer's LGPL licence?** Only if its Metal renderer proves worth it after M2.
- [ ] **Metadata enrichment** (TMDB artwork, ratings) and **scrobbling** (Trakt, Simkl). Both
      add real value and real scope. Not currently planned.
