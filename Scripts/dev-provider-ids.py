#!/usr/bin/python3
"""Which ids does an Xtream provider carry, and do they match Simkl's?

Development aid, read-only. The login comes from the environment and is never written anywhere:

    PANOP_DEV_XTREAM='http://host:9191|user|pass' Scripts/dev-provider-ids.py

Prints, for films and series: how many entries, which id-like fields exist and how often they are
filled, and how many TMDB ids appear on Simkl's public trending lists (a proxy for matching, since
Simkl takes TMDB ids on every call). """
import json, os, re, sys, urllib.parse, urllib.request
from collections import Counter

raw = os.environ.get("PANOP_DEV_XTREAM")
if not raw or raw.count("|") != 2:
    sys.exit("set PANOP_DEV_XTREAM='url|username|password'")
base, user, password = raw.split("|")

def get(url, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": "panop-dev/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.load(response)

def panel(action):
    query = urllib.parse.urlencode({"username": user, "password": password, "action": action})
    return get(f"{base}/player_api.php?{query}")

source = open(os.path.join(os.path.dirname(__file__), "..", "Panop/Services/Simkl/SimklConfig.swift")).read()
client_id = re.search(r'clientID = "([^"]+)"', source).group(1)
simkl_query = f"client_id={client_id}&app-name=panop&app-version=dev"

def filled(value):
    return value not in (None, "", 0, "0", [], {})

library = {}
for kind, action in (("movie", "get_vod_streams"), ("series", "get_series")):
    entries = panel(action)
    print(f"\n== {kind}: {len(entries)} entries")
    fields = Counter()
    for entry in entries:
        for key, value in entry.items():
            if filled(value):
                fields[key] += 1
    idlike = {k: n for k, n in fields.items() if re.search(r"id|imdb|tmdb|tvdb|trakt|mal", k, re.I)}
    print("id-like fields (filled):")
    for key, count in sorted(idlike.items(), key=lambda item: -item[1]):
        print(f"  {key:20} {count:6}  {100 * count / max(len(entries), 1):5.1f}%")
    tmdb = [str(e.get("tmdb_id") or e.get("tmdb") or "") for e in entries]
    ids = {t for t in tmdb if t.isdigit() and int(t) > 0}
    print(f"distinct TMDB ids: {len(ids)}   entries sharing one: {sum(1 for t in tmdb if t.isdigit() and int(t) > 0) - len(ids)}")
    imdb = [e for e in entries if filled(e.get("imdb")) or filled(e.get("imdb_id"))]
    print(f"entries with an IMDb id: {len(imdb)}")
    library[kind] = ids

print("\n== overlap with Simkl's public trending lists (TMDB ids)")
for kind, path in (("movie", "movies"), ("series", "tv")):
    for period in ("today", "week", "month"):
        try:
            items = get(f"https://data.simkl.in/discover/trending/{path}/{period}_500.json?{simkl_query}")
        except Exception as error:
            print(f"  {kind} {period}: {error}")
            continue
        wanted = {str(i.get("ids", {}).get("tmdb")) for i in items if i.get("ids", {}).get("tmdb")}
        print(f"  {kind:6} {period:5}: {len(wanted):3} on Simkl, {len(wanted & library[kind]):3} in this library")

print("\nSimkl accepts a TMDB id on every write (history, scrobble), so a provider TMDB id is enough to record a watch.")
