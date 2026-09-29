## What and why

<!-- What changed, and what problem it solves. Link an issue if there is one. -->

## Verification

<!-- Paste the actual result line, not a claim that it passed. -->

```
swift test --package-path Packages/PanopKit
```

Platforms built (tick what you actually ran):

- [ ] iOS
- [ ] tvOS
- [ ] macOS
- [ ] Not applicable, this change does not touch the app target

## Invariants

Confirm each, or say why it does not apply. Full reasoning is in AGENTS.md.

- [ ] Nothing under `Packages/PanopKit/Sources` imports an Apple-only framework
- [ ] `URLSession` and `XMLParser` uses are guarded with `#if canImport(...)`
- [ ] LumeEngine is still a submodule path dependency, not a URL dependency
- [ ] No KSPlayer dependency was added (it is GPL-3.0)
- [ ] Any new test `ModelConfiguration` sets `cloudKitDatabase: .none`
- [ ] No `@Query` is bound against the cloud container
- [ ] No retry or reconnect logic was added inside an engine adapter
- [ ] Any new dependency has a `THIRD-PARTY-NOTICES.md` entry in this PR
- [ ] No fixtures, media, or playlists committed
