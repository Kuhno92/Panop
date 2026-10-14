import Foundation

/// Replies in the shape sportapi.ai really sends (see docs/sportapi-notes.md), with invented clubs and players: the
/// repository carries none of the service's data.
enum SampleReplies {
    static let day = """
    {"success": true, "date": "2026-10-14", "data": [
      {"id": 101, "home_id": 11, "away_id": 12, "date": "2026-10-14", "datetime": "2026-10-14 20:45:00",
       "kickoff_utc": "2026-10-14T18:45:00Z", "updated_at": "2026-10-14T20:25:12Z",
       "home_score": 0, "away_score": 1, "result": -1, "status": "LIVE", "minute": "79'", "stage": "",
       "league_id": 53, "league_name": "Second Division", "league_geo": "GB-ENG", "league_zone": "England",
       "home_team": "Northgate Rovers", "home_short": "Northgate", "home_logo": "wiki-abc123.png",
       "away_team": "Harbour United", "away_short": "Harbour", "away_logo": "espn-376.png",
       "penalty_home": null, "penalty_away": null, "winner": "away"},
      {"id": "102", "home_id": "13", "away_id": 14, "kickoff_utc": "2026-10-15T19:00:00Z", "status": "Scheduled",
       "home_score": null, "away_score": null, "minute": "", "league_id": 7, "league_name": "Premier Cup",
       "home_team": "Alder Town", "away_team": "Birch City", "home_short": "", "away_short": "Birch"},
      {"home_team": "Nobody", "away_team": "No id"},
      {"id": 104, "status": "Suspended", "minute": "12'", "home_team": "A", "away_team": "B"},
      {"id": 105, "status": "FT", "kickoff_utc": "2026-10-14T16:00:00.000Z", "home_score": 2, "away_score": 2,
       "penalty_home": 4, "penalty_away": 3, "home_team": "C", "away_team": "D"}
    ]}
    """

    static let fixture = """
    {"success": true, "fixture": {"id": 101, "home_id": 11, "away_id": 12, "kickoff_utc": "2026-10-14T18:45:00Z",
      "home_score": 0, "away_score": 1, "ht_home": 0, "ht_away": 0, "status": "LIVE", "minute": "45+2'",
      "league_id": 53, "league_name": "Second Division", "home_team": "Northgate Rovers", "away_team": "Harbour United",
      "home_stadium": "Northgate Park", "home_coach": "A. Coach", "away_coach": "B. Coach",
      "events": [
        {"event_type": "substitution", "team_side": "home", "player_name": "Sam Field", "minute": "48'",
         "extra_info": "Jo Wright"},
        {"event_type": "goal", "team_side": "away", "player_name": "Ben Reed", "minute": "12'", "extra_info": null},
        "not an event"
      ]}}
    """

    static let events = """
    {"success": true, "fixture_id": 101, "data": [
      {"id": 1, "event_type": "yellow_card", "team_side": "home", "player_name": "Al Stone", "minute": "10'"},
      {"id": 2, "event_type": "goal", "team_side": "away", "player_name": "Ben Reed", "minute": "12'"},
      {"id": 3, "event_type": "assist", "team_side": "away", "player_name": "Cy Lane", "minute": "12'"},
      {"id": 4, "event_type": "red_card", "team_side": "home", "player_name": "Al Stone", "minute": "70'"},
      {"id": 5, "event_type": "var_check", "team_side": "home", "player_name": "", "minute": "71'"}
    ]}
    """

    static let lineups = """
    {"success": true, "fixture_id": 101, "available": true, "data": {
      "home": {"starters": [
        {"name": "Keeper One", "position": "Goalkeeper", "shirt": 1, "is_captain": false, "mins_played": 0},
        {"name": "D1", "position": "Defender", "shirt": 2}, {"name": "D2", "position": "Defender", "shirt": 3},
        {"name": "D3", "position": "Centre Back", "shirt": 4}, {"name": "D4", "position": "Right Back", "shirt": 5},
        {"name": "M1", "position": "Defensive Midfielder", "shirt": 6, "is_captain": true},
        {"name": "M2", "position": "Midfielder", "shirt": 8}, {"name": "M3", "position": "Attacking Midfielder", "shirt": 10},
        {"name": "F1", "position": "Left Winger", "shirt": 7}, {"name": "F2", "position": "Striker", "shirt": 9},
        {"name": "F3", "position": "Forward", "shirt": 11}],
       "subs": [{"name": "Reserve", "position": "Substitute", "shirt": 12}]},
      "away": {"starters": [], "subs": []}}}
    """

    static let noLineups = """
    {"success": true, "fixture_id": 5, "available": false, "data": null}
    """

    static let stats = """
    {"success": true, "fixture_id": 101, "available": true, "data": {
      "home": {"shots": 20, "shots_on_target": 10, "shots_off_target": 10, "fouls": 12, "total_passes": 248,
               "pass_accuracy": 77, "tackles": 8, "tackle_success": 50, "saves": 11, "yellow_cards": 2},
      "away": {"shots": "25", "fouls": 12}}}
    """

    static let standings = """
    {"success": true, "data": [
      {"position": 2, "team": {"id": 12, "name": "Harbour United", "short_name": "Harbour", "slug": "harbour", "logo": "espn-376.png"},
       "played": 10, "won": 6, "draw": 2, "lost": 2, "goals_for": 15, "goals_against": 9, "goal_difference": 6,
       "points": 20, "form": [{"result": "W", "date": "2026-09-05"}, {"result": "D"}, {"result": "L"}, {"result": "?"}]},
      {"position": 1, "team": {"id": 11, "name": "Northgate Rovers", "logo": ""},
       "played": 10, "won": 7, "draw": 2, "lost": 1, "goals_for": 16, "goals_against": 7, "points": 23, "form": []},
      {"position": 3, "team": "broken"}
    ]}
    """

    static let leagues = """
    {"success": true, "data": [
      {"country": "England", "geo": "GB-ENG", "leagues": [
        {"id": 53, "name": "Second Division", "domestic": 1, "format": "league", "has_standings": true,
         "has_fixtures": true, "fixtures_count": 552, "teams_count": 24},
        {"id": 7, "name": "Premier Cup", "format": "cup", "has_standings": false}]},
      {"country": "Africa", "leagues": [{"id": 123, "name": "Continental Cup", "format": "cup", "has_standings": false}]}
    ]}
    """
}
