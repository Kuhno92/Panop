#!/usr/bin/env bash
#
# Records real sportapi.ai responses, to read the shapes the documentation leaves out (ids, live minute, standings,
# lineups, headers, logo format). It is the spike of the sports hub (docs/sportapi-notes.md has what it found).
#
#   Scripts/record-sportapi-fixtures.sh            about 25 requests of the free plan's 2,000 a day
#
# The key is read from .secrets/.sportapi (git-ignored, one line, nothing else), or the file named by
# SPORTAPI_KEY_FILE. It is handed to curl through a private header file, so it is on no command line and never printed.
#
# Output goes to Packages/PanopKit/Tests/PanopSportsTests/Generated/, which is git-ignored on purpose: the terms of
# sportapi.ai are unknown, and the repository never carries a third party's data (CLAUDE.md: fixtures are generated).
# The fixtures that ARE committed are written by hand, in the same shape, with invented teams.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="${SPORTAPI_KEY_FILE:-$ROOT/.secrets/.sportapi}"
OUT="$ROOT/Packages/PanopKit/Tests/PanopSportsTests/Generated"
BASE="https://sportapi.ai/api"

if [[ ! -s "$KEY_FILE" ]]; then
    echo "error: no key in $KEY_FILE. Put the sportapi.ai key there, alone on one line." >&2
    exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT"/*.json "$OUT"/*.headers "$OUT"/*.bin
HEADERS="$(mktemp)"
trap 'rm -f "$HEADERS"' EXIT
chmod 600 "$HEADERS"
printf 'X-Api-Key: %s\n' "$(tr -d '\r\n ' <"$KEY_FILE")" >"$HEADERS"

requests=0

# call NAME PATH [extra curl args]: one request, the body in NAME.json (or .bin), the response headers in NAME.headers.
call() {
    local name="$1" path="$2"
    shift 2
    local code
    requests=$((requests + 1))
    code="$(curl -s -m 40 -H "@$HEADERS" -D "$OUT/$name.headers" -o "$OUT/$name.body" -w '%{http_code}' "$@" "$BASE$path" || echo 000)"
    # The type decides the extension, so a logo that is SVG is not mistaken for JSON.
    local file="$OUT/$name.bin"
    if grep -qi '^content-type: *application/json' "$OUT/$name.headers" 2>/dev/null; then
        file="$OUT/$name.json"
    fi
    mv "$OUT/$name.body" "$file"
    # Nothing that identifies the account stays in a file, whatever the server echoes.
    sed -i '' -E '/^[Ss]et-[Cc]ookie/d' "$OUT/$name.headers"
    printf '  %-26s HTTP %s  %s bytes  %s\n' "$name" "$code" "$(wc -c <"$file" | tr -d ' ')" "$path"
}

# pick FILE PYTHON-EXPRESSION: reads the JSON of FILE as `d` and prints what the expression gives.
pick() {
    python3 -c "
import json, sys
d = json.load(open('$1'))
$2
" 2>/dev/null || true
}

echo "==> Recording into ${OUT#"$ROOT"/}"
today="$(date -u +%F)"
yesterday="$(date -u -v-1d +%F)"
tomorrow="$(date -u -v+1d +%F)"

call leagues /leagues
call standings-leagues /standings/leagues
call fixtures-today "/fixtures/date/$today"
call fixtures-yesterday "/fixtures/date/$yesterday"
call fixtures-tomorrow "/fixtures/date/$tomorrow"

# Fixtures: one finished, one live or at half time, one still to come, and a league and a team to ask about.
ids="$(pick "$OUT/fixtures-yesterday.json" "
rows = d.get('data') or []
fin = next((r for r in rows if str(r.get('status')) in ('FT', 'AET', 'PENS')), None)
print('FINISHED', (fin or {}).get('id', ''))
")"
ids+=$'\n'"$(pick "$OUT/fixtures-today.json" "
rows = d.get('data') or []
live = next((r for r in rows if str(r.get('status')) in ('LIVE', 'HT')), None)
fin = next((r for r in rows if str(r.get('status')) in ('FT', 'AET', 'PENS')), None)
sched = next((r for r in rows if str(r.get('status')).lower() == 'scheduled'), None)
print('LIVE', (live or {}).get('id', ''))
print('TODAYFINISHED', (fin or {}).get('id', ''))
print('SCHEDULED', (sched or {}).get('id', ''))
")"
finished="$(awk '$1=="FINISHED"{print $2}' <<<"$ids")"
[[ -n "$finished" ]] || finished="$(awk '$1=="TODAYFINISHED"{print $2}' <<<"$ids")"
live="$(awk '$1=="LIVE"{print $2}' <<<"$ids")"
scheduled="$(awk '$1=="SCHEDULED"{print $2}' <<<"$ids")"
echo "    finished=${finished:-none} live=${live:-none} scheduled=${scheduled:-none}"

if [[ -n "$finished" ]]; then
    call fixture-finished "/fixtures/$finished"
    call events-finished "/fixtures/$finished/events"
    call stats-finished "/fixtures/$finished/stats"
    call lineups-finished "/fixtures/$finished/lineups"
fi
if [[ -n "$live" ]]; then
    call fixture-live "/fixtures/$live"
    call events-live "/fixtures/$live/events"
    call lineups-live "/fixtures/$live/lineups"
fi
if [[ -n "$scheduled" ]]; then
    call fixture-scheduled "/fixtures/$scheduled"
    call lineups-scheduled "/fixtures/$scheduled/lineups"
fi

# A league, a team and their logo, from whatever ids the responses carry.
league="$(pick "$OUT/fixture-finished.json" "
f = d.get('data', d)
print(f.get('league_id') or (f.get('league') or {}).get('id') or '')
")"
if [[ -z "$league" ]]; then
    league="$(pick "$OUT/leagues.json" "
def walk(x):
    if isinstance(x, dict):
        if 'id' in x and ('name' in x or 'slug' in x):
            yield x['id']
        for v in x.values():
            yield from walk(v)
    elif isinstance(x, list):
        for v in x:
            yield from walk(v)
print(next(iter(walk(d)), ''))
")"
fi
team="$(pick "$OUT/fixture-finished.json" "
f = d.get('data', d)
print(f.get('home_team_id') or (f.get('home') or {}).get('id') or '')
")"
echo "    league=${league:-none} team=${team:-none}"

if [[ -n "$league" ]]; then
    call standings-league "/standings/$league"
    call league-detail "/leagues/$league"
    call topscorers "/leagues/$league/topscorers"
fi
if [[ -n "$team" ]]; then
    call team "/teams/$team"
    call team-logo "/teams/$team/logo"
fi

# What a rejected key looks like (does not use the real key).
requests=$((requests + 1))
code="$(curl -s -m 40 -H 'X-Api-Key: invalid' -D "$OUT/unauthorized.headers" -o "$OUT/unauthorized.json" -w '%{http_code}' \
    "$BASE/fixtures/date/$today" || echo 000)"
printf '  %-26s HTTP %s\n' unauthorized "$code"

echo "==> $requests requests made"
ls "$OUT" | sed 's/^/    /'
