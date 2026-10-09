# Releasing to TestFlight

Panop is always signed and uploaded under the **personal** Apple developer team (`4HUJUM5AUG`, "Nico Kuhn"), never the
company team. The App Store Connect record is **PanopTV**, bundle ID `com.panop.Panop`, one record for iOS, tvOS and macOS.

Once, in the developer portal and App Store Connect (only the account holder can):

- The App ID `com.panop.Panop` has the iCloud (CloudKit) capability, and the container `iCloud.com.panop.Panop` exists.
- The Xcode account of the personal team is signed in (Xcode → Settings → Accounts), so `-allowProvisioningUpdates` can
  make the distribution certificate and profiles.
- Testers: internal ones (App Store Connect users) get builds at once; for a public link, add an external group, and
  the first build of each version goes through Beta App Review. Say in the review notes that Panop ships no content and
  plays only sources the user adds.

For each build:

```bash
Scripts/bump-build.sh                       # a build number higher than the last upload
git commit -am "chore: build N"             # a build comes from a commit
Scripts/archive-testflight.sh all           # archives iOS, tvOS and macOS into build/archives/
Scripts/archive-testflight.sh all --upload  # the same, and sends each to App Store Connect
```

A release gets a tag with its version, `v0.1.0`, on the commit its first build was made from. The version is
`MARKETING_VERSION` in the project; the build number is `CURRENT_PROJECT_VERSION`.

The source is at https://github.com/Kuhno92/Panop (linked from About), as the GPL-3.0 licence asks.

## From GitHub

Pushing a tag named for a version starts `.github/workflows/release.yml`: it runs the tests (`ci.yml`), then archives and
uploads iOS, tvOS and macOS to App Store Connect, each as its own job. The tag must match `MARKETING_VERSION`.

```bash
git tag -a v0.1.1 -m "Panop 0.1.1" && git push origin v0.1.1
```

The build number is the workflow's run number (`Scripts/bump-build.sh`), so it only goes up; after a release made from
GitHub, a build made by hand must use a higher number than the last run's.

It needs three repository secrets, made once, from an App Store Connect API key (Users and Access, Integrations, App Store
Connect API; the App Manager role) under the personal team: `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (the `.p8` file
as base64: `base64 -i AuthKey_XXXX.p8 | pbcopy`). Xcode signs with the key (cloud signing), so no certificate is stored.

The tests run on every commit to `main`, on pull requests, and by hand (Actions, CI, Run workflow); the upload to
App Store Connect runs only for a version tag, and only after the tests pass on it. This repository is public, so the
minutes are free (private repositories get a few thousand a month, and macOS minutes count ten times).
