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

## iCloud: the CloudKit schema must reach production

The app mirrors the person's data (favourites, history, playlists, and the sports hub's choices and key) into a private
CloudKit database with SwiftData (ADR 0009, 0011). CloudKit has two environments:

- **Development**: used by builds run from Xcode. A new record type is created here **by the first save** of such a record
  from a development build signed in to an iCloud account.
- **Production**: used by TestFlight and App Store builds. It only gets a record type when the schema is **deployed** from
  development in the CloudKit Dashboard. Until then those records silently do not sync.

The record types are the model's class names with the prefix `CD_`, and every attribute is a field with that prefix:

| Model | Record type | Notes |
|---|---|---|
| `UserContentState` | `CD_UserContentState` | favourites, history, hidden titles |
| `PlaylistRecord` | `CD_PlaylistRecord` | playlists; `CD_encryptedLogin` is an encrypted field |
| `CategoryPreference` | `CD_CategoryPreference` | category order and hiding |
| `SportsPreference` | `CD_SportsPreference` | leagues, teams, setup flag, tab, channels chosen |
| `SportsKeyRecord` | `CD_SportsKeyRecord` | `CD_encryptedKey` is an encrypted field; `CD_removed` marks a key taken out |
| `VPNConfigRecord` | `CD_VPNConfigRecord` | `CD_encryptedConfig` is an encrypted field (the WireGuard file, private key included); `CD_removed` marks one taken out. **New: deploy the schema to production before a TestFlight build, or it does not sync** |

### Once: let `cktool` read the schemas

1. In the CloudKit Dashboard (https://icloud.developer.apple.com, team 4HUJUM5AUG, container `iCloud.com.panop.Panop`) open
   *Profile > Tokens & Keys* and create a **management token**.
2. Save it on the Mac that does the releases: `xcrun cktool save-token --type management` (it asks for the token; it goes
   into the Keychain and is never written to the repository).

### Before a release that adds or changes a cloud model

1. **Create the record types in development.** Run a **Debug** build (from Xcode, signed with the team) on a Mac, iPhone or
   Apple TV that is signed in to iCloud, with iCloud sync on in Settings, and **use every feature that saves a record**:
   add a playlist, favourite a channel, then in Sports enter a key (with "Keep the key in iCloud" on), choose a league and a
   team, and play a match's channel. Leave the app open a minute so the export runs.
2. **See what production lacks:** `Scripts/check-cloudkit-schema.sh`. It exports both schemas and lists the record types and
   fields in development that production does not have (exit status 1 when there are any).
3. **Deploy:** Dashboard > the container > *Schema* > **Deploy Schema Changes...** (development to production). Production
   fields cannot be removed afterwards, so look at the list first.
4. **Confirm:** run `Scripts/check-cloudkit-schema.sh` again; it should say there is nothing to deploy.
5. **Check on two devices** with a TestFlight build (production): enter the key on one, see it arrive on the other; change
   the leagues on one, see them on the other; take the key out on one, see it go from the other. ADR 0009 and 0011 are
   still "not verified against a real iCloud account" until this has been done once.

A model that only *adds* optional or defaulted fields is a lightweight migration for the person's existing store, and the
new fields are added to the CloudKit schema the same way; nothing needs to be reset.

