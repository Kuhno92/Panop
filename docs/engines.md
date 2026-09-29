# Playback engines and the FFmpeg coexistence problem

Panop links four playback engines. Three of them carry their own copy of FFmpeg. Getting them
into one binary is the single most fragile part of the build, and the failure modes are
obscure, so this document exists to save the next person a day.

---

## Why four engines

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
| KSPlayer *(not linked)* | Metal rendering, strong tvOS performance | **GPL-3.0**, see below |

### KSPlayer is not shipped

KSPlayer is **GPL-3.0** by default, with LGPL sold separately as a commercial license. Linking
it would force Panop to be GPL-3.0 rather than MIT, and would forfeit App Store distribution,
because GPLv3's terms conflict with the App Store's in a way only the copyright holder can
resolve.

The adapter is written and lives behind the `PANOP_ENABLE_KSPLAYER` compilation condition, but
**its dependency is not in the project**. Anyone building from source may add it and accept
GPL-3.0 for their own build. Do not add it to the shipped configuration.

---

## How multiple FFmpegs coexist

**Not through linker flags.** There is no `-force_load`, no `-no_warn_duplicate_libraries`, and
no allowable-client trickery. Coexistence comes entirely from how each engine packages its
FFmpeg, and each uses a different mechanism.

Panop's shipped configuration contains two copies (VLCKit's and LumeEngine's). A third
(KSPlayer's, via FFmpegKit) appears only in a local build with `PANOP_ENABLE_KSPLAYER`. All
three are described because the interactions matter.

### VLCKit: hidden by static linking

VLCKit ships a prebuilt xcframework with FFmpeg statically linked inside `libvlccore` with
hidden symbol visibility. No `av*` symbols are exported and no C headers are vended to Swift.
It is effectively invisible to the other engines.

**Integration:** SwiftPM URL dependency, exact version. Add the product to the Frameworks build
phase only.

### KSPlayer: the public one (only if you enable it)

KSPlayer depends on FFmpegKit, whose `Libavcodec`, `Libavutil` and friends are genuinely public
in the app's module compile. It is the copy most likely to collide with another engine's.

Panop does not link it (see above), so in the shipped configuration this copy is absent. It
matters if you enable `PANOP_ENABLE_KSPLAYER` for a local build: do so and the collision
described below becomes live.

### LumeEngine: isolated, and fragile about it

LumeEngine isolates its FFmpeg 9 through three mechanisms, **all of which are load-bearing**:

1. `.library(type: .dynamic)`, so its FFmpeg symbols stay inside `LumeEngine.framework` under
   the two-level namespace.
2. `-enable-library-evolution`, so its `CFFmpeg` C module never enters the consumer's module
   compile.
3. `internal import CFFmpeg`, so the module is not re-exported.

Header nesting prevents *path* collisions but cannot prevent C-namespace type redefinition.
That is what mechanism 2 is for.

---

## The trap

`-enable-library-evolution` can only be expressed as `.unsafeFlags`, and **SwiftPM forbids
unsafe flags in version-resolved dependencies**. LumeEngine's manifest therefore gates the flag
on whether its own `#filePath` contains `/checkouts/`:

- Consumed as a **path or submodule** dependency, the flag applies. Its FFmpeg stays isolated.
- Consumed by **URL**, SwiftPM resolves it into `/checkouts/`, the flag is silently dropped,
  `CFFmpeg` leaks into the app's compile, and it collides with KSPlayer's FFmpeg.

The resulting error names a pixel format constant and looks nothing like a dependency problem:

```
'AV_PIX_FMT_OHCODEC' from module 'CFFmpeg' is not present in
definition of 'enum AVPixelFormat' in module 'Libavutil'
```

**Therefore: LumeEngine is a git submodule at `vendor/LumeEngine`, referenced as a local path
package.**

Two caveats on how strong this requirement is in Panop's shipped configuration. KSPlayer is not
linked, so the copy of FFmpeg most likely to collide is absent, and VLCKit's is statically
hidden and vends no Swift module. So a URL dependency might happen to work today. It is still
the wrong choice, for two reasons that do not depend on KSPlayer:

- LumeEngine's own documentation lists VLCKit among the conflicting cases, and its symbol
  isolation is the mechanism that makes that safe. Relying on VLCKit's hiding rather than
  LumeEngine's isolation means one upstream packaging change breaks the build in a way whose
  error message points nowhere useful.
- LumeEngine is pre-1.0 with an explicitly unfrozen API, so it should be pinned to a reviewed
  commit regardless, which is exactly what a submodule gives.

Enabling `PANOP_ENABLE_KSPLAYER` makes the collision live and the requirement absolute.

Converting it to a version dependency looks like tidying up. It is a build break. `AGENTS.md`
calls this out because it is the most likely mistake for anyone, human or agent, who sees a
submodule and assumes it should be a normal dependency.

Because LumeEngine is a dynamic SwiftPM library rather than a binary target, Xcode does **not**
auto-embed it. It needs an explicit Embed Frameworks phase with Code Sign On Copy, plus
`LD_RUNPATH_SEARCH_PATHS` of `@executable_path/Frameworks` (and
`@executable_path/../Frameworks` for macOS).

---

## KSPlayer framework fixups

**Only relevant if you enable `PANOP_ENABLE_KSPLAYER` for a local build.** Recorded here so the
knowledge is not lost if the licensing situation changes.

KSPlayer's embedded frameworks need three corrections before an app containing them can be
accepted. They would be applied by a script running as the first build phase of the app target
with `ENABLE_USER_SCRIPT_SANDBOXING = NO`.

1. **Underscores in `CFBundleIdentifier`.** iOS rejects embedded frameworks whose bundle ID
   contains an underscore.
2. **Shallow framework layout on macOS.** macOS requires the deep `Versions/A/` layout. A
   shallow bundle with `_CodeSignature` at its root produces "unsealed contents present in the
   root directory".
3. **`MinimumOSVersion` mismatch on tvOS.** The plist declares a version that disagrees with
   the Mach-O slice, producing ITMS-90208 **at upload time only**. This does not surface in a
   normal build, so archive for tvOS at least once after adding KSPlayer.

The script also re-signs with an explicit `--identifier` to avoid error 90334.

---

## Integration order

Add engines one at a time, verifying a build on all three platforms between each. Debugging one
new FFmpeg against a known-good build is tractable; debugging two at once is not.

1. **AVPlayer.** System framework, nothing to add. Ship this alone first.
2. **VLCKit.**
3. **LumeEngine** as a submodule and path dependency, dynamic, embedded, signed.

KSPlayer is not part of this sequence because it is not linked.

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

- Its `LumePlayer` facade exposes no event stream, and its underlying `PlayerSession` is
  private to it. Reconnect handling, Picture in Picture, and Now Playing therefore need an
  app-side facade built directly on `PlayerSession`.
- One session plays one URL. Changing channel means a full teardown and a new session, so
  channel-switch latency needs measuring against the other engines.

The engine deliberately never retries on its own schedule. Reconnect and backoff are Panop's
job, which matches where that policy lives for the other three engines anyway.
