---
description: Build the app for iOS, tvOS and macOS
---

Build Panop for every supported platform:

```bash
Scripts/build-all-platforms.sh
```

Notes:

- This takes a while and uses several GB of disk. The script already passes
  `-clonedSourcePackagesDirPath`, which is mandatory; see AGENTS.md for why.
- No tvOS simulator runtime is installed on this machine, so the tvOS step is a compile-only
  check against a generic destination. That catches most platform mistakes but cannot verify
  runtime behaviour. Install the runtime with `xcodebuild -downloadPlatform tvOS` if you need
  to actually launch on Apple TV.
- Clean up afterwards: `rm -rf /tmp/panop-dd-*`

If you only changed `Packages/PanopKit`, run `/test-fast` instead. It is far quicker and
sufficient.
