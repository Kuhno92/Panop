---
description: Run the PanopKit logic tests (seconds, no simulator)
---

Run the portable core's test suite:

```bash
swift test --package-path Packages/PanopKit
```

This is the fast loop and should be your default. It needs no simulator and no Xcode project.

If a test fails, fix the cause rather than the assertion. If you need to narrow the run:

```bash
swift test --package-path Packages/PanopKit --filter <TestSuiteName>
```

Do not fall back to `xcodebuild test` for logic that lives in `Packages/PanopKit`. If something
there seems to need a simulator, it is probably importing an Apple-only framework, which
violates the portable-core rule in AGENTS.md.
