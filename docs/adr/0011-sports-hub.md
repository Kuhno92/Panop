# 0011. A sports hub on the person's own key, synced through their iCloud

**Status:** accepted, **not yet verified on two real devices with a real iCloud account** (as ADR 0009).

## Context

The owner asked for a sports hub: today's matches of the leagues and teams the person follows, with scores, tables and
line-ups, and the channel of their playlist that shows each match. The data source is sportapi.ai (football only). It
has no channel data, a free plan of 2,000 requests a day **per key**, and no published terms for use in an app.

## Decision

1. **The person brings their own key.** The app ships none. The key is entered in Settings, checked against the service
   before it is kept, and read from the Keychain at each call. Nothing is sent to a server of the developer's.
2. **Everything about the hub syncs through the person's iCloud (ADR 0009):** the leagues and favourite teams, whether
   setup is done, whether the tab is shown, the channels chosen for a league, and **the key**. The first four are rows of one
   kind in the cloud container (`SportsPreference`, per profile; CloudKit allows nothing unique, so a read keeps the
   newest of a choice written twice). The key is an encrypted field (`SportsKeyRecord`, like `PlaylistRecord.encryptedLogin`),
   decided by `SportsKeySync.decide`, a copy of `PlaylistLogins.decide` with one addition: a key taken out on one device
   leaves a mark, so another device lets go of its own instead of sending it back. A Settings switch turns the key's travel off.
3. **The budget is the service's word, not a count.** Every reply carries `x-ratelimit-limit/remaining/reset`; all of a
   person's devices share one key and so one budget, which a local count would get wrong. The last 5% is kept for what the
   person asks for (pulling to refresh, opening a match); a live match is asked about every minute, then more slowly; one
   request is made for what three screens ask at once; what was fetched is kept as it came and shown, marked old, when the
   service cannot be reached.
4. **One day call covers every league**, so the cost does not depend on how many leagues are followed. The service counts a
   day in Central European time; a person's own day is mapped onto one or two of its days.
5. **The channel of a match is found on the device, from the guide.** Team names are read the way a guide writes them (accents,
   "ue" for "ü", "vs" in all its spellings, club dressing left out, an alias table for nicknames); a programme is scored by
   what it says and when. A programme that names one team is never sure enough to start on its own; a generic title such as
   "Football Live" still matches when the description names the teams; sport that names no team is offered to choose from.
6. **Crests are the service's public files** (`https://sportapi.ai/logos/<file>`): no key, no request of the budget. A team
   with none gets its initials on a colour of its own, stable across launches.
7. **`PanopSports` is a separate portable target**, so a licence decision can drop it, as `PanopSimkl` can.

## Consequences

- The new records must be **deployed from the development to the production CloudKit schema** in the CloudKit Dashboard
  before a TestFlight or App Store build, or they silently do not sync.
- With sync on, the key is also in the local store in plain (the same trade-off ADR 0009 accepted for playlist logins).
- sportapi.ai's terms for use in an app are unknown: ask in writing before a release that includes the hub, and keep the
  answer in `docs/`.
- Football only. Goal alerts, a score overlay while playing, multi-view and the WebSocket feed are not done.
