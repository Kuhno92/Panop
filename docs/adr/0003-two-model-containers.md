# 0003. Two SwiftData ModelContainers

**Status:** accepted

## Context

Panop stores two very different kinds of data:

- **Catalog**: channels, movies, series, EPG. Large (80,000+ entries), rebuilt from the
  provider, and entirely derivable. Browsing must stay fast on an Apple TV HD.
- **User state**: favorites, watch progress, settings, provider credentials. Small,
  irreplaceable, and must follow the user across devices.

The obvious design is one container with CloudKit mirroring enabled.

## Decision

Use two separate `ModelContainer`s.

| | Catalog | Cloud |
|---|---|---|
| CloudKit | `cloudKitDatabase: .none` | `.private(...)` |
| `@Query` bound | Yes, exclusively | **Never** |
| `@Attribute(.unique)` | Used freely | Forbidden |
| Relationships | Yes | None |
| Optionality | As modelled | Every property optional or defaulted |

Credentials in the cloud container use `@Attribute(.allowsCloudEncryption)`.

## Consequences

Two independent constraints force this.

**CloudKit's schema rules.** Mirroring forbids `@Attribute(.unique)`, requires every property
to be optional or defaulted, and disallows relationships. A catalog modelled under those rules
loses its uniqueness guarantees and its cascade behaviour, and gets slower.

**Import churn re-evaluates queries.** A mirrored container re-runs every active `@Query`
during CloudKit import. With a large catalog on tvOS that is enough to freeze the UI. Splitting
means catalog browsing is entirely unaffected by sync activity.

The cost is that the split cannot be retrofitted cheaply, so both containers are created early
even while the cloud one is nearly empty. Deletion also needs explicit handling: with no
cascade relationship from playlist to content, a helper must remove dependent rows, and it must
be used from both the UI and the sync reconciler.

Because CloudKit entitlements change behaviour, **every test `ModelConfiguration` must set
`cloudKitDatabase: .none`**, or tests crash on entitled hosts.
