# App Store Connect: what to enter

For the app record **PanopTV** (bundle ID `com.panop.Panop`). Everything is for you to paste; the account holder's login is
needed to enter it. Sizes and rules are Apple's as of this writing, so check the form if one has changed.

## Links

| Field | Value |
|---|---|
| Privacy Policy URL | https://github.com/Kuhno92/Panop/blob/main/PRIVACY.md |
| Support URL | https://github.com/Kuhno92/Panop/issues |
| Marketing URL (optional) | https://github.com/Kuhno92/Panop |

## App information

| Field | Value |
|---|---|
| Name | PanopTV |
| Subtitle (30) | Your own TV, movies and series |
| Primary category | Entertainment |
| Secondary category | Utilities |
| Copyright | 2026 Nico Kuhn |
| Content rights | The app does not contain, show or access third-party content of its own: it plays the sources the user adds. |

Subtitle in German: Dein eigenes TV, Filme, Serien

## Version information (English)

**Promotional text (170)**
A fast, native player for the live TV, movies and series you already have. Guide-first, quick to zap, and the same on
iPhone, iPad, Apple TV and Mac.

**Description**
PanopTV is a native player for your own IPTV sources. Add an Xtream login, an M3U link or an M3U file, and watch your live
channels, films and series on iPhone, iPad, Apple TV and Mac. PanopTV ships no content: it only plays the sources you
add yourself.

LIVE TV
- Channels start fast, and the list stays quick with tens of thousands of entries
- A full TV guide, what is on now and next, with catch-up where your provider offers it
- Channels that are the same channel in HD, UHD and SD are listed once; pick the version in the list or while it plays
- Favourites and recently watched, categories you can arrange and hide

MOVIES AND SERIES
- Posters with ratings and how far you watched, categories, sorting and search
- Suggestions made on your device from your own library and what you watch
- Resume where you stopped

BUILT FOR EVERY SCREEN
- Made for Apple TV with the remote, for the Mac with the pointer and keyboard, for the phone with a thumb
- Play something and keep browsing: the stream keeps playing behind the app
- Several players behind one choice, so a stream that one cannot play falls through to another

YOURS
- Profiles, an adult-content filter with an optional PIN
- Your favourites, history and playlists can follow you between your devices through your own iCloud
- No account, no ads, no tracking. The developer collects nothing

PanopTV is free software under the GNU GPL v3. The source is on GitHub.

**Keywords (100)**
iptv,m3u,xtream,player,live tv,epg,tv guide,streams,playlist,series,movies,hls

**What's new in this version**
First version for TestFlight.

## Version information (German)

**Werbetext**
Ein schneller, nativer Player für das Live-TV, die Filme und Serien, die du schon hast. Mit TV-Programm, schnellem Umschalten
und gleich auf iPhone, iPad, Apple TV und Mac.

**Beschreibung**
PanopTV ist ein nativer Player für deine eigenen IPTV-Quellen. Füge einen Xtream-Zugang, einen M3U-Link oder eine
M3U-Datei hinzu und sieh deine Live-Sender, Filme und Serien auf iPhone, iPad, Apple TV und Mac. PanopTV liefert keine
Inhalte mit: Es spielt nur die Quellen ab, die du selbst hinzufügst.

LIVE-TV
- Sender starten schnell, und die Liste bleibt auch mit Zehntausenden Einträgen flott
- Ein vollständiges TV-Programm, was jetzt und als Nächstes läuft, mit Catch-up, wo dein Anbieter es bietet
- Derselbe Sender in HD, UHD und SD steht nur einmal in der Liste; die Version wählst du in der Liste oder während der Wiedergabe
- Favoriten und zuletzt gesehen, Kategorien, die du ordnen und ausblenden kannst

FILME UND SERIEN
- Poster mit Bewertung und Fortschritt, Kategorien, Sortierung und Suche
- Vorschläge, die auf deinem Gerät aus deiner Bibliothek und deinem Sehverhalten entstehen
- Weiterschauen, wo du aufgehört hast

FÜR JEDEN BILDSCHIRM GEMACHT
- Für Apple TV mit der Fernbedienung, für den Mac mit Zeiger und Tastatur, für das iPhone mit dem Daumen
- Etwas abspielen und weiter stöbern: Der Stream läuft hinter der App weiter
- Mehrere Player hinter einer Auswahl: Was einer nicht abspielen kann, übernimmt ein anderer

DEINS
- Profile, ein Jugendschutzfilter mit optionaler PIN
- Favoriten, Verlauf und Playlists können dich über dein eigenes iCloud auf deinen Geräten begleiten
- Kein Konto, keine Werbung, kein Tracking. Der Entwickler sammelt nichts

PanopTV ist freie Software unter der GNU GPL v3. Der Quellcode liegt auf GitHub.

**Schlüsselwörter**
iptv,m3u,xtream,player,live tv,epg,tv programm,streams,playlist,serien,filme,hls

## App privacy (the "nutrition label")

Answer **Data Not Collected**. The developer receives nothing: the lists and history stay on the device, and iCloud is
the person's own private database, which the developer cannot read. If Simkl is switched on in a later build, that is the
person's own account with Simkl; add "Data Linked to You, App Functionality" for it then.

## Age rating

Answer the questionnaire honestly for an app that plays content the user supplies. Apple's form asks about what the app
shows; Panop shows none itself, but a user's source can include anything, so the safe answers are **Unrestricted Web
Access: Yes** (a user can open any stream address) and mature content frequency **Infrequent/Mild**, which gives 17+. A
lower rating risks a rejection if a reviewer opens a source with adult channels.

## App Review information

- **Sign-in required:** No.
- **Contact:** your name, phone and email (required, only Apple sees them).
- **Notes** (paste):

  PanopTV ships no content. It is a player for the user's own sources: an Xtream login, an M3U link or an M3U file.
  To try it, open Settings (or the Home screen's "Add playlist"), choose "M3U link" and enter this public test playlist:
  `https://iptv-org.github.io/iptv/languages/deu.m3u` (free public channels). Live TV lists the channels; choosing
  one plays it. Movies and Series appear for sources that have them (an Xtream login). There is no account and no
  in-app purchase. iCloud sync is optional and off until the user turns it on.

## Export compliance

Already answered in the app (`ITSAppUsesNonExemptEncryption = false`): only the encryption the system provides.

## Screenshots (required for a store release, not for TestFlight)

| Platform | Size |
|---|---|
| iPhone (6.9") | 1320 x 2868 |
| iPad (13") | 2064 x 2752 |
| Apple TV | 3840 x 2160 (or 1920 x 1080) |
| Mac | 2880 x 1800 (or 1280 x 800, 1440 x 900, 2560 x 1600) |

The UI tests already export screenshots (`xcrun xcresulttool export attachments`); for the store, use a playlist with real
artwork.

## TestFlight (the minimum for external testers)

| Field | Value |
|---|---|
| Beta App Description | PanopTV plays your own TV, movies and series from an Xtream login or an M3U playlist. It ships no content. Try adding a source, browsing the TV guide, and playing something, on iPhone, Apple TV and Mac. |
| Feedback email | the address testers write to |
| Beta App Review contact and notes | as under App Review information above |
| What to Test | Add a source; Live TV list, search, categories and the TV guide; channels with several versions (the button at the end of a row); playing, switching channel, going back to browse with the stream still playing; Movies and Series browsing and resume. |
