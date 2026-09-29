# 0004. Logic lives in a local SwiftPM package

**Status:** accepted

## Context

The obvious layout for an Apple app is one Xcode target with folders for models, services, and
views. It works, and shipping apps do it at scale.

But it has two costs that matter here. Testing any logic requires building the app target and
booting a simulator, a loop measured in minutes. And nothing prevents parsing logic from
reaching for a UIKit type, so layering erodes quietly.

## Decision

All logic that is not UI and not persistence lives in `Packages/PanopKit`, a local SwiftPM
package with six targets: `PanopCore`, `PanopPlaylist`, `PanopXtream`, `PanopEPG`,
`PanopCatalog`, `PanopPlayback`.

The Xcode app target holds SwiftData models, SwiftUI views, and the playback engine adapters,
and depends on the package. The dependency arrow never reverses.

SwiftData `@Model` classes stay in the app target and never appear in package signatures. The
app supplies a `SwiftDataCatalogStore` conforming to the `CatalogStore` protocol that
`PanopCatalog` is written against.

## Consequences

`swift test --package-path Packages/PanopKit` runs the whole logic suite in seconds with no
simulator. This is the loop developers and coding agents actually use, and making it fast
changes how often tests get run.

Module boundaries are enforced by the compiler rather than by discipline. Parsing cannot
accidentally depend on a view.

It also makes the core portable, which is a precondition for the Android, Windows, and Linux
plans recorded in ADR 0007.

The costs are real but small: SwiftData models cannot be shared into the package, so import
code maps between package value types and models at the boundary; and SwiftUI previews of views
that depend on package types rebuild the package.
