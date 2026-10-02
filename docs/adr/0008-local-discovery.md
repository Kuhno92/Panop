# 0008. Suggest from the library, on the device

**Status:** accepted

## Context

Panop shows Movies and Series by the provider's categories. People expect rails like Netflix
(trending, because you watched, new releases) but a suggestion is only useful when the title is in
their own library. A provider can list tens of thousands of titles, and what someone watched is
private.

Sources that rank what is popular have terms that matter for a paid app. TMDB's terms treat an app
that charges as commercial and want a paid agreement, so TMDB is not used at all. Simkl is free
below $150 a month of revenue and licensed above it. Wikimedia page views and Wikidata are CC0.

## Decision

1. **Every rail is drawn from the library.** Candidates are bounded, indexed reads of the catalog
   (top rated, recent, by TMDB id, by history). A title that is not in the library cannot appear.
2. **Rails are a pure function** (`PanopDiscover.RailBuilder`): the library slice, the history, the
   hidden and finished sets and a date go in; rails come out. No machine learning, no clock, no I/O.
   Thresholds live in one `RailRules` value.
3. **The history never leaves the device.** The one outside signal is a public trending list, the
   same for everyone, joined to the library by TMDB id.
4. **Built off the main thread and cached.** `DiscoveryStore` builds on its own context and writes
   the result as JSON; Home draws the cache at once and rebuilds, debounced, after a change.
5. **Adult, hidden, hidden-category, watched and posterless titles are never suggested.**
6. **Simkl is optional and isolated.** `PanopSimkl` holds all of it. With no `client_id` nothing is
   asked of Simkl and no Simkl screen is shown. It supplies the trending list, and for a connected
   account a plan-to-watch rail, an exclusion of what is finished there, and recording of finished
   titles. Dropping the module removes it; trending can fall back to a Wikimedia-based source.

## Consequences

- Rails depend on the provider's data: movies on a typical panel carry no genre, so there are genre
  rails for series only. Titles without a TMDB id cannot join a trending list.
- Simkl needs a registered app, its terms ask for the list to be named as Simkl's, and a
  commercial licence is due above the revenue threshold. Account calls follow its rules: batches,
  no timers, a check of what changed before reading lists.
- Finished titles are recorded as history entries, not live scrobbles, so Simkl shows no "now
  watching" and resume points stay on the device.
