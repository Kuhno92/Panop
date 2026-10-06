# Playback engines and the FFmpeg coexistence problem

Panop ships three playback engines and carries a fourth adapter that is not linked. Two of the
shipped engines bring their own copy of FFmpeg. Getting them into one binary is the single most
fragile part of the build, and the failure modes are obscure, so this document exists to save
the next person a day.

---

## Why several engines

IPTV is not just HLS. Providers serve:

- raw MPEG-TS over HTTP (extremely common, and **AVPlayer cannot play it**)
- HLS, both live and VOD
- MKV and MP4 VOD files
- HEVC nearly everywhere, AV1 increasingly
- occasionally RTSP

No single engine covers all of it well while also giving native Picture in Picture, AirPlay,
Now Playing, and good battery life. So Panop ships four and lets the user choose, with an
ordered fallback list when one fails to start a stream.

| Engine | Use it for | Weakness |
|---|---|---|
| AVPlayer / AVKit | HLS, VOD, anything Apple handles natively | No raw MPEG-TS, narrow container support |
| VLCKit | Universal fallback, exotic containers | Large binary, weak system integration |
| LumeEngine | Long-running live IPTV streams | Pre-1.0, API not frozen |
| KSPlayer *(iOS, tvOS)* | FFmpeg with a Metal renderer | **GPL-3.0**: Panop is GPL-3.0 because of it |

### KSPlayer

KSPlayer is **GPL-3.0**; linking it makes Panop GPL-3.0 (ADR 0010). It is linked on iOS, iPadOS and tvOS through
`Packages/KSPlayerBridge`, last in the default order because it has not been measured on a real provider. Not on
macOS: FFmpegKit's macOS frameworks are packaged with `Info.plist` at the bundle root and Xcode refuses to embed them.
A real-provider run needs an iOS build; the matrix test runs on macOS only.

---

## How multiple FFmpegs coexist

**Not through linker flags.** There is no `-force_load`, no `-no_warn_duplicate_libraries`, and
no allowable-client trickery. Coexistence comes entirely from how each engine packages its
FFmpeg, and each uses a different mechanism.

Panop's iOS and tvOS builds contain four copies (VLCKit's, LumeEngine's, AetherEngine's and KSPlayer's, via
FFmpegKit); macOS three. All are described because the interactions matter.

### VLCKit: hidden by static linking

VLCKit ships a prebuilt xcframework with FFmpeg statically linked inside `libvlccore` with
hidden symbol visibility. No `av*` symbols are exported and no C headers are vended to Swift.
It is effectively invisible to the other engines.

**Integration:** SwiftPM URL dependency, exact version. Add the product to the Frameworks build
phase only. Done, at **4.0.0-a24**: the only SwiftPM-distributed line is the VLCKit 4 alpha, since
3.7.x has no `Package.swift`. Expect API churn when bumping it; the adapter is the only place that
imports it. The package checkout is about 2.7 GB in the shared clone directory.

**Things about libVLC that are not in its documentation** (each cost a crash or a bug to learn):

- **Never let it render into a view that is not on screen.** Its OpenGL video output aborts the
  whole process (an assertion in `vout_display_opengl_Prepare`, on its own render thread). The
  engine therefore holds `play()` until its surface is in a window, and drops the drawable if the
  surface leaves one mid-playback.
- **Never release a `VLCMediaPlayer` on the main thread.** Its destructor joins a libVLC thread that
  can be waiting on the main queue, and the app deadlocks. `VLCPlayerHolder` hands the last
  reference to a background queue wherever the engine dies, and `stop()` runs off the main thread too.
- **Delegate classes must be `nonisolated`.** libVLC calls them from its own threads, and under the
  project's default main-actor isolation Swift asserts the main queue on entry and traps.
- **Buffering progress is 0.0 to 1.0**, not a percentage. Read as 0 to 100 it left every stream stuck
  in `.buffering`, which the coordinator answers by reconnecting.
- **`:start-time` is ignored** by VLCKit 4 (every spelling measured as absent), so a resume position
  is applied by seeking on the first frame. That is acceptable for video on demand, the only kind
  the coordinator resumes.
- **There is no "opened but not playing" state.** `load` only prepares the media; a failure to open
  arrives as a `.failed` event after `play()`. It does report one for garbage and missing files.
- **An unreachable stream is logged, not reported.** libVLC logged `TLS session handshake error` and
  `HTTP connection failure` for an HTTPS stream, fired no error event, and stayed "opening" for good.
  The coordinator then waited out its start timeout and called it a dropped connection.
  `VLCConnectionWatch` listens to the library log for those two lines and fails the engine, so the
  coordinator can retry and fall back. libVLC's logger is library-wide and is set in one assignment, so
  anything else that wants the log (a test's file logger) goes through `install(alongside:)`.
  The failure itself was **intermittent**: the same stream failed every run for an hour (`error while
  writing: 4`, an interrupted system call, during the handshake) and then played in every run, with
  the host and its certificate chain fine throughout. Cause not established; AVPlayer played the
  stream throughout.

### KSPlayer: public, so it is wrapped

KSPlayer depends on FFmpegKit, whose `Libavcodec`, `Libavutil` and friends are genuinely public in a compile that
imports it, and would collide with AetherEngine's and Lume's:

```
'AV_CODEC_ID_AHX' from module 'AetherLibavcodec' is not present in
definition of 'enum AVCodecID' in module 'Libavcodec'
```

So the app never imports it. `Packages/KSPlayerBridge` is a dynamic library with `-enable-library-evolution` and
`InternalImportsByDefault`, so KSPlayer's modules do not appear in what the app sees (UIKit and AppKit are the only
public imports). The `-enable-library-evolution` flag is an unsafe flag, so the package must stay a path
dependency. Building with `SWIFT_ENABLE_EXPLICIT_MODULES=NO` was needed once while this was being set up and is not
needed now.

### LumeEngine: isolated, and fragile about it

LumeEngine isolates its FFmpeg 9 through three mechanisms, **all of which are load-bearing**:

1. `.library(type: .dynamic)`, so its FFmpeg symbols stay inside `LumeEngine.framework` under
   the two-level namespace.
2. `-enable-library-evolution`, so its `CFFmpeg` C module never enters the consumer's module
   compile.
3. `internal import CFFmpeg`, so the module is not re-exported.

Header nesting prevents *path* collisions but cannot prevent C-namespace type redefinition.
That is what mechanism 2 is for.

### AetherEngine: dynamic frameworks, and a stand-in for libdovi

AetherEngine's FFmpeg is **FFmpegBuild**: dynamic frameworks with their own names (`AetherLibavcodec.framework` and the rest), embedded in the app's
Frameworks folder. The names differ from Lume's and VLC's, so nothing collides at load time, and the app target
imports only AetherEngine, so no FFmpeg module reaches its compile.

It also depends on `libdovi`, a *static* xcframework with a module map. LumeEngine's FFmpeg is one too. Xcode copies
each static xcframework's module map to `Build/Products/<configuration>/include/module.modulemap`, and two of them
there stop the build: `Multiple commands produce '.../include/module.modulemap'`. The way out that keeps AetherEngine
unmodified is `Packages/LibDovi`, a local package named like the real one so that it overrides it in the graph, with the
same C functions that AetherEngine calls and bodies that do nothing. Cost: Dolby Vision profile 7 is not converted to 8.1.
If either engine ever stops shipping a static module-mapped xcframework, the real `LibDovi` can come back by removing the
local package reference from the project.

**It crashed on live TV.** On a real provider's interlaced H.264 live channels AetherEngine 7.27.2 raised SIGSEGV inside
FFmpeg's `avfilter_free`, called from its `DeinterlaceFilter.ensureGraph`, with the hardware and the software
deinterlacer alike. Films and episodes play. The default order therefore leaves it out of live TV (see
[engine-matrix.md](engine-matrix.md)).

**It reconnects by itself.** A live source that cannot be reached is retried inside the engine (five attempts over about
fifteen seconds were seen), and there is no public option to turn that off, so a failed load takes that long to be
reported. The coordinator's load timeout still applies. It is the one adapter that does not report a failure at once.

---

## The trap

`-enable-library-evolution` can only be expressed as `.unsafeFlags`, and **SwiftPM forbids
unsafe flags in version-resolved dependencies**. LumeEngine's manifest therefore gates the flag
on whether its own `#filePath` contains `/checkouts/`:

- Consumed as a **path or submodule** dependency, the flag applies. Its FFmpeg stays isolated.
- Consumed by **URL**, SwiftPM resolves it into `/checkouts/`, the flag is silently dropped,
  `CFFmpeg` leaks into the app's compile, and it collides with AetherEngine's and KSPlayer's FFmpeg.

The resulting error names a pixel format constant and looks nothing like a dependency problem:

```
'AV_PIX_FMT_OHCODEC' from module 'CFFmpeg' is not present in
definition of 'enum AVPixelFormat' in module 'Libavutil'
```

**Therefore: LumeEngine is a git submodule at `vendor/LumeEngine`, referenced as a local path
package.**

Two caveats on how strong this requirement is. The other copies are isolated too (KSPlayer behind its bridge,
VLCKit's statically hidden), so a URL dependency might happen to work today. It is still
the wrong choice, for two reasons:

- LumeEngine's own documentation lists VLCKit among the conflicting cases, and its symbol
  isolation is the mechanism that makes that safe. Relying on VLCKit's hiding rather than
  LumeEngine's isolation means one upstream packaging change breaks the build in a way whose
  error message points nowhere useful.
- LumeEngine is pre-1.0 with an explicitly unfrozen API, so it should be pinned to a reviewed
  commit regardless, which is exactly what a submodule gives.

With AetherEngine and KSPlayer linked, the collision is live and the requirement absolute.

Converting it to a version dependency looks like tidying up. It is a build break. `AGENTS.md`
calls this out because it is the most likely mistake for anyone, human or agent, who sees a
submodule and assumes it should be a normal dependency.

Because LumeEngine is a dynamic SwiftPM library rather than a binary target, Xcode does **not**
auto-embed it. It needs an explicit Embed Frameworks phase with Code Sign On Copy, plus
`LD_RUNPATH_SEARCH_PATHS` of `@executable_path/Frameworks` (and
`@executable_path/../Frameworks` for macOS).

---

## KSPlayer framework fixups

KSPlayer's embedded frameworks (FFmpegKit's) may need corrections before an app containing them can be accepted.
Not yet done, because nothing has been archived or uploaded:

1. **Underscores in `CFBundleIdentifier`.** iOS rejects embedded frameworks whose bundle ID contains one.
2. **Shallow framework layout on macOS.** macOS requires the deep `Versions/A/` layout. This is why KSPlayer is not
   linked on macOS today: the embed step fails with "contains Info.plist, expected
   Versions/Current/Resources/Info.plist". A build phase that rebuilds each framework deeply would lift it.
3. **`MinimumOSVersion` mismatch on tvOS.** ITMS-90208 **at upload time only**. Archive for tvOS before uploading.

If any appears, the fix is a script that runs as the first build phase of the app target with
`ENABLE_USER_SCRIPT_SANDBOXING = NO`, and re-signs with an explicit `--identifier` (error 90334).

---

## Integration order

Add engines one at a time, verifying a build on all three platforms between each. Debugging one
new FFmpeg against a known-good build is tractable; debugging two at once is not.

1. **AVPlayer.** System framework, nothing to add. Ship this alone first.
2. **VLCKit.**
3. **LumeEngine** as a submodule and path dependency, dynamic, embedded, signed.

4. **AetherEngine**, then **KSPlayer** behind its bridge (iOS and tvOS).

---

## Disk usage

VLCKit's xcframework alone is around 865 MB, and KSPlayer brings FFmpegKit's. Every
`-derivedDataPath` without a shared package clone directory re-downloads and re-expands the
whole graph, several GB each time. Always pair them:

```bash
xcodebuild ... -derivedDataPath /tmp/panop-dd-ios \
               -clonedSourcePackagesDirPath ~/Library/Developer/Panop-SharedSPM
```

A few parallel builds without this will fill a disk.

---

## LumeEngine specifics

LumeEngine is MIT licensed and bundles LGPL FFmpeg 9, so its product must stay dynamically
linked for relinkability. It is pre-1.0 with an explicitly unfrozen API, so it is pinned to a
specific commit rather than tracking a version range.

Two integration gaps to plan around:

- Its `LumePlayer` facade exposes no event stream, but `PlayerSession` is public in `LumeEngineCore`
  and `import LumeEngine` re-exports it. The adapter (`LumePlaybackEngine`) is built on the session,
  which has the typed events, `stalled`, and a start position applied before the demuxer streams.
  Picture in Picture and Now Playing still need building on top of it.
- One session plays one URL. Changing channel means a full teardown and a new session, so
  channel-switch latency needs measuring against the other engines.

The engine deliberately never retries on its own schedule. Reconnect and backoff are Panop's
job, which matches where that policy lives for the other three engines anyway.

### What integrating it showed

- **Embed it explicitly.** A source-built `.dynamic` package product is linked as
  `@rpath/LumeEngine.framework`, but Xcode does not copy it into the app: only binary xcframeworks
  such as VLCKit are embedded for you. The build succeeds, the tests pass, and the app then cannot
  launch on any machine but the one that built it. The app target has an Embed Frameworks phase
  (sign on copy) for it. Check `Contents/Frameworks` in a Release build after touching the project.
- **Its enums are not frozen** (library evolution), so every `switch` over `PlayerEvent`,
  `PlayerSession.State` or `EngineError.Code` needs `@unknown default`.
- **Failure arrives before its reason.** The session sets `.failed` and only then emits the `.error`
  event that explains it, so the adapter waits briefly for the error before reporting the failure.
- **Turn off its HTTP auto-reconnect** (`enableReconnect`, on by default). Reconnect policy is the
  coordinator's, and a quiet reconnect hides the failure from it.
- **A connection that ends is an error, as it should be.** A server closing a finite stream shows up
  as `av_read_frame: Input/output error`, mapped to `.network`, so the coordinator reconnects.
- **Garbage bytes** open as `avformat_open_input: Input/output error`, which maps to the retryable
  `.openFailed`, not `.unsupportedFormat`. The coordinator retries before moving on.
- **A TLS failure is its own error.** `PlaybackError.Code.secureConnectionFailed`, from libVLC's
  `TLS session handshake error` line, is not retryable: the handshake is done by the engine's own
  network stack, so asking it again gets the same answer, and the coordinator moves to the next
  engine (which, with a different stack, may succeed) without the retries and their delay. A plain
  `HTTP connection failure` stays a retryable `.network`.
- **Multivariant HLS is slow to open, so Lume is handed one variant.** FFmpeg's HLS demuxer opens
  every variant and audio group before it starts: 2.9 to 3.3 s on ZDF (six video variants, eight
  audio and subtitle entries), against 0.15 s for AVPlayer and 0.08 s for libVLC. Probe limits do
  not help. FFmpeg never switches variants as the network changes, so naming one loses no adaptive
  behaviour. `HLSVariantPicker` fetches the playlist (4 s limit, 512 KB limit, the item's headers),
  `HLSMultivariant.simplified` keeps the best variant under 6 Mbps with its own audio group and
  absolute addresses, and Lume opens that as a local file with `protocol_whitelist` and
  `allowed_extensions` set. Measured on ZDF: 970, 943, 958, 930, 841 ms against 3323, 3197, 3278,
  3069, 3106 ms for the whole playlist. Any failure falls back to the original address, and the
  temporary file is deleted in `stop()`. AVPlayer takes HLS first in the default order, so this
  only shows when Lume is the chosen engine.
- **A quiet connection is not a live one, for tests.** A test server that sends a short stream
  and then holds the connection open makes the player probe until its 15 second read timeout.
  `LocalStreamServer(holdOpen: true)` loops the body instead, as a live channel keeps coming.
  Closing instead is read as the stream failing, so a finite stream cannot stand in for a live one.
- **Tests sharing a process interfere.** With the engine suites running in parallel, a LumeEngine
  open failed with an I/O error one millisecond after opening whenever the VLC and AVPlayer suites
  ran at the same time. The mechanism is not established; libVLC tearing players down in the
  background is the suspect. `.engineGate` (`PanopTests/EngineGate.swift`) lets one real-engine test
  run at a time, across suites, and the failure stopped. Put new engine suites under it.
