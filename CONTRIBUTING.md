# Contributing to Panop

## Getting set up

```bash
git clone --recurse-submodules <repo-url> Panop
cd Panop
Scripts/setup.sh
```

`setup.sh` is safe to re-run. It installs git hooks and builds the vendored developer tools.
**Do not install SwiftLint, SwiftFormat, or lefthook globally.** They are vendored through the
root `Package.swift` and pinned in `Package.resolved` so everyone runs identical versions.

## The development loop

```bash
# Use this constantly. Seconds, no simulator.
swift test --package-path Packages/PanopKit

# Only when you touched the app target
Scripts/build-all-platforms.sh
```

Most logic belongs in `Packages/PanopKit`, where it is fast to test. If you find yourself
needing a simulator to test parsing or API logic, that logic is probably in the wrong place.

## Before opening a pull request

- [ ] `swift test --package-path Packages/PanopKit` passes
- [ ] The app builds for iOS, tvOS, and macOS if you touched the app target
- [ ] Pre-commit hooks pass (they run SwiftFormat then SwiftLint)
- [ ] No new dependency without a `THIRD-PARTY-NOTICES.md` entry in the same commit
- [ ] No generated fixtures, media, or playlists committed

## Invariants

These are in [AGENTS.md](AGENTS.md) with full reasoning. Summarised:

1. **`Packages/PanopKit` imports no Apple-only framework.** The core must keep compiling on
   Linux, Windows, and Android. A SwiftLint rule and a Linux CI job enforce this.
2. **LumeEngine stays a submodule path dependency**, never a URL dependency.
3. **KSPlayer stays behind `Packages/KSPlayerBridge`.** Importing it (or FFmpegKit) in the app target breaks the
   build, because its FFmpeg collides with AetherEngine's and LumeEngine's.
4. **Every test `ModelConfiguration` sets `cloudKitDatabase: .none`.**
5. **Never bind `@Query` against the cloud container.**
6. **No retry or reconnect logic inside an engine adapter.**

Each exists because breaking it produces a failure that is slow and confusing to diagnose. If
one seems wrong, the reasoning is in [docs/adr/](docs/adr/); please argue with the ADR rather
than working around the rule.

## Style

- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/).
  `feat(player): add engine fallback ordering`, `fix(epg): correct timezone offset parsing`.
  Branches mirror the type: `fix/epg-timezone-drift`.
- **Tests:** swift-testing (`import Testing`) for new tests. XCTest only where required, such
  as UI tests and performance measurement.
- **Comments explain why, not what.** Well-named code already says what it does. Write a
  comment when there is a non-obvious constraint, a subtle invariant, or a workaround whose
  reason would otherwise be lost.

## Licensing

Panop is GPL-3.0. Two things to be careful about:

**`reference/` is off limits as a source of code.** It holds third-party clones for occasional
design reference and is gitignored. `reference/Lume` is AGPL-3.0. Reading it to understand an
approach is fine. Copying from it, including scripts and configuration, is not, and would make
Panop undistributable. See [ADR 0001](docs/adr/0001-clean-room-mit.md).

**Check the license before adding a dependency.** GPL-3.0, LGPL (dynamically
linked) and MIT are fine. AGPL and licences with extra restrictions are not. Contributions are accepted under
GPL-3.0. See [ADR 0010](docs/adr/0010-link-ksplayer-gpl.md).

## Using AI coding agents

Point the agent at [AGENTS.md](AGENTS.md) first. `CLAUDE.md` is a symlink to it, so agents that
look for either will find the same guide. It documents the invariants above along with the
failure each one prevents, which is the part that is expensive to rediscover.
