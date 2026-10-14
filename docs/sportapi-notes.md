# sportapi.ai: what the API really returns

Recorded on 2026-10-14 with `Scripts/record-sportapi-fixtures.sh` (about 35 requests) and a free key. The raw
responses are not committed (the terms of sportapi.ai are unknown, and the repository carries no third party's
data); the committed test fixtures are written by hand in the same shape, with invented teams.

Base `https://sportapi.ai/api`, header `X-Api-Key`. Every JSON reply is `{"success": true, ...}`.

## Quota

- **Every response carries the quota:** `x-ratelimit-limit: 2000`, `x-ratelimit-remaining`, `x-ratelimit-reset` (epoch
  seconds of the next 00:00 UTC). So the app reads its budget from the server, and counts nothing itself.
- A `304 Not Modified` still costs a request (remaining went down by one), so `If-None-Match` saves bandwidth only.
- A request without a key, or a wrong one, is `401 {"success": false, "error": "API key required. ..."}`.
- Not seen: a 429 reply and its headers. Treat 429 as "limit reached until `x-ratelimit-reset`" (the headers are
  expected to be there).

## Endpoints, as seen

| Call | Notes |
|---|---|
| `GET /fixtures/date/{YYYY-MM-DD}` | **One call returns every league** (23 fixtures for today). Fields: `id`, `home_id`, `away_id`, `league_id`, `league_name`, `league_zone`, `league_geo`, `date`, `datetime` (CET/CEST), `kickoff_utc`, `updated_at`, `status`, `minute` (text such as `"79'"`, present only while playing), `stage`, `home_score`, `away_score`, `result`, `penalty_home/away`, `winner`, `home_team`, `home_short`, `home_logo` (a file name), the same for away. |
| `GET /fixtures/{id}` | `{"fixture": {...}}`: the fields above plus `ht_home/ht_away`, stadium, city, coach, founded for both teams, and `events`. |
| `GET /fixtures/{id}/events` | `data[]`: `id`, `event_type` (seen: `goal`, `assist`, `yellow_card`, `substitution`), `team_side` (`home`/`away`), `player_name`, `minute` (`"48'"`), `extra_info` (the player coming on, for a substitution). |
| `GET /fixtures/{id}/lineups` | `available: false, data: null` for smaller matches. Otherwise `data.home/away` with `starters[11]` and `subs[]`: `name`, `position` (text: `Defender`, `Defensive Midfielder`, `Substitute`), `shirt`, `is_captain`, `mins_played`. **No formation and no grid positions**: the pitch is drawn from the position names. |
| `GET /fixtures/{id}/stats` | `available`, then `data.home/away`: `shots`, `shots_on_target`, `shots_off_target`, `fouls`, `total_passes`, `pass_accuracy`, `tackles`, `tackle_success`, `saves`, `yellow_cards`. No possession. |
| `GET /standings/{leagueId}` | `data[]` ordered by `position`: `team{id,name,short_name,slug,logo}`, `played`, `won`, `draw`, `lost`, `goals_for`, `goals_against`, `goal_difference`, `points`, `form[]` (each: `result` W/D/L, `date`, teams, scores, `is_home`). **An empty list for a cup** (`has_standings: false`). |
| `GET /leagues` | `data[]` is **countries** (41): `country`, `geo`, `leagues[]` each with `id`, `name`, `domestic`, `format` (`cup`...), `has_standings`, `has_fixtures`, `fixtures_count`, `teams_count`. |
| `GET /standings/leagues` | 117 leagues, flat: `id`, `name`, `slug`, `zone`, `geo`. |
| `GET /teams/{id}` | `team{id,name,short_name,league_id,country,city,coach_name,stadium_name,founded_year,logo_file}`, `matches[50]` (past and coming), `leagues[]`. |

**Statuses seen:** `Scheduled`, `LIVE`, `FT`, `PENS`, `Cancelled`, `Postponed`. The documentation also lists `HT` and
`AET`. Anything else must decode as "unknown", not fail.

## Logos

- Fixtures, standings and teams give a **file name** (`espn-376.png`, `wiki-<hash>.png`).
- **`https://sportapi.ai/logos/<file>` is public**: a 500-pixel PNG of about 40 KB, no key, with `ETag` and
  `Last-Modified`. It does not count against the quota (no key to count). A missing file is a 404 with a JSON body.
- `/teams/{id}/logo` also works but needs the key and costs a request. Not needed.
- So the existing `ImagePipeline` (ImageIO, disk cache) loads crests as they are. Whether hot-linking sportapi.ai's
  logos is allowed is part of the open terms question.

## What this changes in the plan

- Team and league **ids exist**, so selections store ids (names kept for display); no name-only fallback needed.
- **The budget comes from the response headers**, not a local ledger. A local count remains only as a fallback.
- **One day call covers all leagues**: the hub's cost is flat in the number of leagues the user picks.
- **Logos cost nothing** and need no key or header: drop the header-aware logo store. Monogram crests remain the
  fallback for a 404 or a missing file name.
- **Lineups carry no formation**: group starters by position name (goalkeeper, defender, midfielder, forward) and draw
  the rows from the counts.
- **No possession**, no xG: the stats view shows what exists (shots, passes, fouls, tackles, saves, cards).
- Live minute is text with an apostrophe: parse the leading number, keep `45+2'` as given.
