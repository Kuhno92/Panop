# Privacy policy for Panop (PanopTV)

Last changed: 2026-10-09

Panop is a player. It ships no channels, films or series; it plays the sources you add yourself. This page says what
happens to your information when you use it. The short version: **the developer collects nothing.** There is no account
with the developer, no analytics, no advertising and no tracking, and nothing is sent to a server run by the developer.

## What Panop stores, and where

- **Your sources** (an M3U link or file, or an Xtream login) and the channel, film and series lists read from them are
  stored on your device. Passwords and logins are kept in the Keychain.
- **What you do in the app** (favourites, what you watched and how far, hidden titles, category choices, profiles, the
  engine that worked for a title) is stored on your device. Playback statistics (how fast a channel started) stay on the
  device too.

## Where information goes

- **Your providers.** Panop connects to the playlist, guide and stream addresses you add, to play them. What those
  servers see (your address, the titles you ask for) is between you and them. The developer has no access to it.
- **Your iCloud, if you turn it on.** Panop can keep your favourites, history and playlists in step across your own devices
  through your private iCloud database (CloudKit). Only you can read it, and the developer cannot. Logins travel in
  it only if you choose that, and encrypted.
- **Simkl, only if you sign in to it.** If a build offers it and you sign in, Panop sends the titles you finished to your
  Simkl account and reads your lists, and it fetches Simkl's public lists of what is popular. Nothing is sent to Simkl
  without your sign-in. Simkl's own policy applies to what it holds.
- **YouTube, only when you tap Trailer.** If your provider gives a film's trailer as a YouTube video, Panop plays it in YouTube's
  own player (iPhone, iPad and Mac) or reads its address from YouTube (Apple TV), so YouTube sees that request and your
  device's address, as in any visit. Nothing is loaded from YouTube until you tap the button, and no one else is told which
  trailer you watch.
- **sportapi.ai, only if you enter a key for it.** The sports hub (today's football matches) uses your own free account at
  sportapi.ai. Panop sends your key and what it asks for (a day's matches, a league's table, a match) to sportapi.ai, and
  loads team crests from its public files. Nothing about your playlists, channels or what you watch is sent: which channel
  shows a match is worked out on your device, from your own guide. The key is kept in the Keychain on your device and, if
  iCloud is on, also travels to your other devices in an end-to-end encrypted field of your own iCloud; you can turn that off
  in Settings, and removing the key removes it from your devices. The leagues and teams you follow and the channels you chose
  for a league travel through your iCloud as well. sportapi.ai's own policy applies to what it holds.
- **Artwork and guide data** are fetched from the addresses your provider gives.

## Children

Panop has no content of its own. What it shows depends on the sources you add. It has an adult-content filter, with an
optional PIN, in Settings.

## Your choices

You can remove a source, forget what you watched, or turn iCloud, Simkl and the sports key off in Settings, and delete the app, which
removes what it stored on the device. Data in your iCloud can be removed in iPhone Settings, Apple Account, iCloud,
Manage Storage.

## Contact

Questions: open an issue at https://github.com/Kuhno92/Panop/issues
