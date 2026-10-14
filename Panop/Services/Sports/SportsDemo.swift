#if DEBUG
    import Foundation
    import PanopCore

    /// The sports hub without the real service, for UI tests, screenshots and trying the screens: `PANOP_DEMO_SPORTS=1`
    /// with `-panop-uitest` gives a key, leagues and teams, and a transport that answers like sportapi.ai with invented
    /// clubs
    /// (no one's real name or crest). `PANOP_DEV_SPORTSAPI` names a file with a real key instead, for a look at real
    /// data
    /// on the developer's own machine; `PANOP_DEV_SPORTS_LEAGUES` lists the league ids to follow then. Debug builds
    /// only.
    enum SportsDemo {
        static let isActive = UITestMode.isActive && ProcessInfo.processInfo.environment["PANOP_DEMO_SPORTS"] == "1"

        private static var devKey: String? {
            guard UITestMode.isActive, let path = ProcessInfo.processInfo.environment["PANOP_DEV_SPORTSAPI"],
                  let text = try? String(contentsOfFile: path, encoding: .utf8)
            else { return nil }
            return SportsKeySync.decode(Data(text.utf8))
        }

        /// The key the in-memory store starts with.
        static var initialKey: String? {
            isActive ? "demo-key" : devKey
        }

        static var transport: (any HTTPTransport)? {
            isActive ? DemoSportsTransport() : nil
        }

        /// What the person follows at the start: leagues 1 and 2 and the first team, or the leagues asked for.
        @MainActor
        static func seed(_ services: AppServices) {
            guard isActive || devKey != nil else { return }
            let sync = services.sportsSync
            if isActive {
                sync.setLeague(
                    SportsLeagueChoice(id: 1, name: "Northern Division", country: "England"),
                    chosen: true,
                    profile: ""
                )
                sync.setLeague(
                    SportsLeagueChoice(id: 2, name: "Kronen Liga", country: "Germany"),
                    chosen: true,
                    profile: ""
                )
                sync.setTeam(
                    SportsTeamChoice(id: 11, name: "Northgate Rovers", short: "Northgate", logo: nil, leagueID: 1),
                    chosen: true, profile: ""
                )
                sync.setSetupDone(true, profile: "")
            } else if let ids = ProcessInfo.processInfo.environment["PANOP_DEV_SPORTS_LEAGUES"] {
                for id in ids.split(separator: ",").compactMap({ Int($0) }) {
                    sync.setLeague(
                        SportsLeagueChoice(id: id, name: "League \(id)", country: ""),
                        chosen: true,
                        profile: ""
                    )
                }
                sync.setSetupDone(true, profile: "")
            }
        }
    }

    /// Answers like sportapi.ai, with clubs that do not exist. Times are relative to now, so the day always has
    /// something
    /// on, something over and something to come.
    final class DemoSportsTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var served = 0

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let path = request.url.path.replacingOccurrences(of: "/api", with: "")
            let used = lock.withLock { () -> Int in served += 1; return served }
            let body = reply(for: path)
            return HTTPResponse(
                statusCode: 200,
                body: (try? JSONSerialization.data(withJSONObject: body)) ?? Data(),
                headers: [
                    "x-ratelimit-limit": "2000", "x-ratelimit-remaining": String(2000 - used),
                    "x-ratelimit-reset": "1893456000"
                ]
            )
        }

        func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
            let response = try await send(request)
            return HTTPStreamResponse(statusCode: response.statusCode, chunks: HTTPChunks([response.body]))
        }

        // MARK: - The world

        private static let teams: [Int: (String, String)] = [
            11: ("Northgate Rovers", "Northgate"), 12: ("Harbour United", "Harbour"), 13: ("Alder Town", "Alder Town"),
            14: ("Birch City", "Birch City"), 15: ("Cedar Athletic", "Cedar"), 16: ("Dune Wanderers", "Dune"),
            17: ("Elm Park", "Elm Park"), 18: ("Fir Albion", "Fir Albion"),
            21: ("Falkenberg SV", "Falkenberg"), 22: ("Rhein 04", "Rhein 04"), 23: ("Nordstadt FC", "Nordstadt"),
            24: ("Alpen United", "Alpen"), 25: ("Bergfeld", "Bergfeld"), 26: ("Seeland", "Seeland")
        ]

        private func reply(for path: String) -> [String: Any] {
            let parts = path.split(separator: "/").map(String.init)
            if parts == ["standings", "leagues"] {
                return ["success": true, "data": []]
            }
            if parts == ["leagues"] {
                return ["success": true, "data": leagues]
            }
            if parts.count == 3, parts[0] == "fixtures", parts[1] == "date" {
                return ["success": true, "data": fixtures(day: parts[2])]
            }
            if parts.count == 2, parts[0] == "fixtures" {
                return ["success": true, "fixture": detail(Int(parts[1]) ?? 0)]
            }
            if parts.count == 3, parts[0] == "fixtures" {
                return matchPart(Int(parts[1]) ?? 0, parts[2])
            }
            if parts.count == 2, parts[0] == "standings" {
                return ["success": true, "data": table(Int(parts[1]) ?? 0)]
            }
            return ["success": true, "data": []]
        }

        /// The events, line-ups and numbers of a match: only the first of the demo's matches has line-ups and numbers.
        private func matchPart(_ id: Int, _ part: String) -> [String: Any] {
            switch part {
            case "events": ["success": true, "data": events(id)]
            case "lineups": id == 101 ? available(lineups) : unavailable
            case "stats": id == 101 ? available(stats) : unavailable
            default: ["success": true, "data": []]
            }
        }

        private func available(_ data: [String: Any]) -> [String: Any] {
            ["success": true, "available": true, "data": data]
        }

        private var unavailable: [String: Any] {
            ["success": true, "available": false, "data": NSNull()]
        }

        private var leagues: [[String: Any]] {
            [
                ["country": "England", "geo": "GB-ENG", "leagues": [
                    [
                        "id": 1,
                        "name": "Northern Division",
                        "format": "league",
                        "has_standings": true,
                        "has_fixtures": true,
                        "teams_count": 8
                    ]
                ]],
                ["country": "Germany", "geo": "DE", "leagues": [
                    [
                        "id": 2,
                        "name": "Kronen Liga",
                        "format": "league",
                        "has_standings": true,
                        "has_fixtures": true,
                        "teams_count": 6
                    ]
                ]],
                ["country": "International", "geo": "", "leagues": [
                    [
                        "id": 3,
                        "name": "Atlantic Cup",
                        "format": "cup",
                        "has_standings": false,
                        "has_fixtures": true,
                        "teams_count": 16
                    ]
                ]]
            ]
        }

        private func fixture(
            _ id: Int, league: Int, _ teams: (Int, Int), kickoff: Date, status: String,
            minute: String? = nil, score: (Int, Int)? = nil
        ) -> [String: Any] {
            let (home, away) = teams
            let names = [
                "1": ("Northern Division", "England"),
                "2": ("Kronen Liga", "Germany"),
                "3": ("Atlantic Cup", "International")
            ]
            let place = names[String(league)] ?? ("", "")
            var result: [String: Any] = [
                "id": id, "home_id": home, "away_id": away, "league_id": league, "league_name": place.0,
                "league_zone": place.1,
                "kickoff_utc": ISO8601DateFormatter().string(from: kickoff), "status": status, "stage": "",
                "home_team": Self.teams[home]?.0 ?? "", "home_short": Self.teams[home]?.1 ?? "",
                "away_team": Self.teams[away]?.0 ?? "", "away_short": Self.teams[away]?.1 ?? ""
            ]
            if let minute {
                result["minute"] = minute
            }
            if let score {
                result["home_score"] = score.0
                result["away_score"] = score.1
            }
            return result
        }

        private func fixtures(day: String) -> [[String: Any]] {
            let now = Date.now
            let minutes = { (value: Double) in now.addingTimeInterval(value * 60) }
            let berlinToday = dayKey(now)
            if day == berlinToday {
                return [
                    fixture(
                        101,
                        league: 1,
                        11,
                        12,
                        kickoff: minutes(-63),
                        status: "LIVE",
                        minute: "63'",
                        score: (1, 1)
                    ),
                    fixture(102, league: 1, (13, 14), kickoff: minutes(-48), status: "HT", score: (0, 0)),
                    fixture(103, league: 1, (15, 16), kickoff: minutes(-170), status: "FT", score: (2, 0)),
                    fixture(104, league: 1, (17, 18), kickoff: minutes(90), status: "Scheduled"),
                    fixture(
                        105,
                        league: 2,
                        21,
                        22,
                        kickoff: minutes(-12),
                        status: "LIVE",
                        minute: "12'",
                        score: (0, 0)
                    ),
                    fixture(106, league: 2, (23, 24), kickoff: minutes(180), status: "Scheduled"),
                    fixture(107, league: 2, (25, 26), kickoff: minutes(-260), status: "FT", score: (3, 1)),
                    fixture(108, league: 3, (11, 21), kickoff: minutes(300), status: "Scheduled")
                ]
            }
            // Another day: in the afternoon and evening, Central European time.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let start = calendar.date(from: DateComponents(
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )) else {
                return []
            }
            let at = { (hour: Double) in start.addingTimeInterval(hour * 3600) }
            return [
                fixture(201, league: 1, (12, 13), kickoff: at(15), status: "Scheduled"),
                fixture(202, league: 1, (14, 11), kickoff: at(17.5), status: "Scheduled"),
                fixture(203, league: 2, (22, 23), kickoff: at(18.5), status: "Scheduled"),
                fixture(204, league: 2, (24, 21), kickoff: at(20.5), status: "Scheduled")
            ]
        }

        private func dayKey(_ date: Date) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }

        private func detail(_ id: Int) -> [String: Any] {
            var base = fixtures(day: dayKey(.now)).first { ($0["id"] as? Int) == id } ?? fixture(
                id,
                league: 1,
                11,
                12,
                kickoff: .now,
                status: "Scheduled"
            )
            base["home_stadium"] = "Northgate Park"
            base["events"] = events(id)
            return base
        }

        private func events(_ id: Int) -> [[String: Any]] {
            guard id == 101 else { return [] }
            return [
                ["id": 1, "event_type": "yellow_card", "team_side": "home", "player_name": "Al Stone", "minute": "10'"],
                ["id": 2, "event_type": "goal", "team_side": "away", "player_name": "Ben Reed", "minute": "23'"],
                ["id": 3, "event_type": "assist", "team_side": "away", "player_name": "Cy Lane", "minute": "23'"],
                [
                    "id": 4,
                    "event_type": "substitution",
                    "team_side": "home",
                    "player_name": "Sam Field",
                    "minute": "46'",
                    "extra_info": "Jo Wright"
                ],
                ["id": 5, "event_type": "goal", "team_side": "home", "player_name": "Max Hale", "minute": "58'"],
                ["id": 6, "event_type": "yellow_card", "team_side": "away", "player_name": "Dan Pike", "minute": "61'"]
            ]
        }

        private func squad(_ names: [String], _ positions: [String]) -> [String: Any] {
            let starters = zip(names, positions).enumerated().map { index, pair in
                [
                    "name": pair.0,
                    "position": pair.1,
                    "shirt": index + 1,
                    "is_captain": index == 5,
                    "mins_played": 63
                ] as [String: Any]
            }
            return ["starters": starters, "subs": [["name": "Reserve Keeper", "position": "Substitute", "shirt": 12]]]
        }

        private var lineups: [String: Any] {
            let home = [
                "Tom Keeper",
                "A Stone",
                "B Marsh",
                "C Dale",
                "D Rowe",
                "E Voss",
                "F Hart",
                "G Lowe",
                "H Cole",
                "Max Hale",
                "J Wood"
            ]
            let away = [
                "Ivo Gate",
                "K Pike",
                "L Fern",
                "M Dunn",
                "N Ross",
                "O Lake",
                "P Kerr",
                "Q Vale",
                "Ben Reed",
                "S Moor",
                "T Hill"
            ]
            let homeShape = [
                "Goalkeeper",
                "Defender",
                "Defender",
                "Defender",
                "Defender",
                "Defensive Midfielder",
                "Midfielder",
                "Attacking Midfielder",
                "Left Winger",
                "Striker",
                "Right Winger"
            ]
            let awayShape = [
                "Goalkeeper",
                "Defender",
                "Defender",
                "Defender",
                "Defender",
                "Midfielder",
                "Midfielder",
                "Midfielder",
                "Midfielder",
                "Striker",
                "Striker"
            ]
            return ["home": squad(home, homeShape), "away": squad(away, awayShape)]
        }

        private var stats: [String: Any] {
            [
                "home": [
                    "shots": 11,
                    "shots_on_target": 4,
                    "total_passes": 312,
                    "pass_accuracy": 81,
                    "fouls": 9,
                    "tackles": 14,
                    "saves": 3,
                    "yellow_cards": 1
                ],
                "away": [
                    "shots": 7,
                    "shots_on_target": 3,
                    "total_passes": 268,
                    "pass_accuracy": 76,
                    "fouls": 12,
                    "tackles": 11,
                    "saves": 5,
                    "yellow_cards": 1
                ]
            ]
        }

        private func table(_ league: Int) -> [[String: Any]] {
            let ids = league == 1 ? [11, 12, 13, 14, 15, 16, 17, 18] : (league == 2 ? [21, 22, 23, 24, 25, 26] : [])
            let forms = [
                ["W", "W", "D", "W", "L"],
                ["W", "D", "W", "W", "D"],
                ["L", "W", "W", "D", "W"],
                ["D", "L", "W", "L", "W"]
            ]
            return ids.enumerated().map { index, id in
                let played = 10
                let won = max(1, 8 - index), drawn = 2, lost = played - won - drawn
                return [
                    "position": index + 1,
                    "team": [
                        "id": id,
                        "name": Self.teams[id]?.0 ?? "",
                        "short_name": Self.teams[id]?.1 ?? "",
                        "logo": ""
                    ] as [String: Any],
                    "played": played, "won": won, "draw": drawn, "lost": max(lost, 0),
                    "goals_for": 22 - index * 2, "goals_against": 8 + index * 2, "goal_difference": 14 - index * 4,
                    "points": won * 3 + drawn,
                    "form": forms[index % forms.count].map { ["result": $0] }
                ]
            }
        }
    }
#endif
