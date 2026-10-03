# 0009. Sync the person's data through their own iCloud

**Status:** accepted, **not yet verified against a real iCloud account**: the App ID and container are not
registered yet (see Consequences).

## Context

Panop keeps the person's own data (favourites, what they watched, hidden titles, category choices, their
playlists) in the *cloud* container (ADR 0003), kept apart from the catalogue so mirroring cannot disturb
browsing. Two things stood in the way of turning mirroring on:

- SwiftData does not degrade without the iCloud entitlement: it fails to open the store. Tests, ad hoc
  builds and a person with no account must all keep working.
- State is keyed by a playlist's id, which a device makes up when the playlist is added. State that syncs
  but names a playlist the other device does not have is meaningless. And a playlist's login lives in each
  device's Keychain, so a playlist that syncs without it cannot be used.

## Decision

1. **Mirroring is an explicit decision from facts** (`CloudSync.decide`): the Settings switch, this build
   carrying the entitlement, an account signed in, and not a test. Anything else opens the store locally and
   says why in Settings. A store that will not open mirrored is opened locally rather than ending the app.
2. **The playlists sync with the state**, so their ids are the same everywhere.
3. **Logins travel with the playlists** in an encrypted field (`.allowsCloudEncryption`) of the playlist's
   record, so a playlist is usable on a second device. This is a switch, on by default, and turning it off
   withdraws the logins from iCloud. The Keychain stays the place a device reads a login from; the record
   only carries it between devices. Who wins when two devices disagree is `PlaylistLogins.decide`.
4. **Changes from other devices are applied on a finished, successful CloudKit import only.** A playlist
   removed elsewhere is removed here (catalogue rows, login, state). A record that is merely missing locally
   (an account switched, a store rebuilt) is never read as a removal, so an empty or reset local store
   cannot cause deletions.
5. **No sandbox or Mac App Store work is part of this.** The app is not sandboxed.

## Consequences

- The container `iCloud.com.panop.Panop` and the App ID `com.panop.Panop` must be registered on the
  developer team before any signed build with these entitlements works. This is done by building once in
  Xcode with the team's account. The test scripts build ad hoc, without entitlements.
- With logins on, a playlist's login is also stored in the local SwiftData store (in plain), not only in the
  Keychain. That is what travels; turning the switch off removes it.
- Local M3U files do not travel (only the record does): on another device such a playlist reports that it
  cannot be read.
- One Simkl account, profiles and the PIN stay on the device for now.
