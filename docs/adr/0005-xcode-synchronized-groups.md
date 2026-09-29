# 0005. File-system-synchronized Xcode groups

**Status:** accepted

## Context

An Xcode project traditionally lists every source file in `project.pbxproj`. That file is
machine-generated, ordering is unstable, and identifiers are opaque. It produces merge
conflicts that are painful for humans and close to unresolvable for coding agents, and adding
a file requires editing it.

Project generators such as XcodeGen and Tuist exist largely to work around this, at the cost of
another tool and another manifest format.

Since Xcode 16, `PBXFileSystemSynchronizedRootGroup` (project `objectVersion = 77`) lets a
folder map to a target directly: every file inside it is a member automatically.

## Decision

Use a plain `.xcodeproj` with synchronized root groups for `Panop/`, `PanopTests/`, and
`PanopUITests/`. No XcodeGen, no Tuist.

## Consequences

**Adding a source file means writing it to disk.** No project file edit, no membership
checkbox, no merge conflict. This is the core of Panop's agent-friendliness claim, and it costs
nothing.

The `.pbxproj` stays small enough to review in a diff, since it describes targets and build
settings rather than enumerating hundreds of files.

The tradeoffs: files in a synchronized folder are members of that target automatically, so
platform-specific exclusion happens through `#if os(...)` in source rather than target
membership. Files that must not be compiled, such as `Info.plist`, need an explicit membership
exception in the project.

This requires Xcode 16 or newer. Panop targets Xcode 26, so that is not a constraint.
