import Foundation

/// Where a player plays, as far as the service's position names say. It gives no formation and no grid, so the pitch
/// is drawn from these.
public enum PositionGroup: Int, Sendable, Equatable, Hashable, Comparable {
    case goalkeeper, defender, midfielder, forward, substitute, other

    public init(positionName: String) {
        let name = positionName.lowercased()
        if name.contains("keeper") {
            self = .goalkeeper
        } else if name.contains("substitute") {
            self = .substitute
        } else if name.contains("midfield") {
            // Before the defenders: "Defensive Midfielder" is a midfielder.
            self = .midfielder
        } else if name.contains("back") || name.contains("defen") || name.contains("sweeper") {
            self = .defender
        } else if name.contains("forward") || name.contains("striker") || name.contains("winger") || name
            .contains("attack")
        {
            self = .forward
        } else {
            self = .other
        }
    }

    public static func < (lhs: PositionGroup, rhs: PositionGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct LineupPlayer: Sendable, Equatable, Hashable, Decodable {
    public var name: String
    public var position: String
    public var shirt: Int?
    public var isCaptain: Bool
    public var minutesPlayed: Int?

    public var group: PositionGroup {
        PositionGroup(positionName: position)
    }

    private enum Keys: String, CodingKey {
        case name, position, shirt
        case isCaptain = "is_captain", minutesPlayed = "mins_played"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        name = container.string(.name) ?? ""
        position = container.string(.position) ?? ""
        shirt = container.int(.shirt)
        isCaptain = container.bool(.isCaptain) ?? false
        minutesPlayed = container.int(.minutesPlayed)
    }

    public init(name: String, position: String, shirt: Int? = nil, isCaptain: Bool = false) {
        self.name = name
        self.position = position
        self.shirt = shirt
        self.isCaptain = isCaptain
        minutesPlayed = nil
    }
}

public struct TeamLineup: Sendable, Equatable, Hashable, Decodable {
    public var starters: [LineupPlayer]
    public var substitutes: [LineupPlayer]

    private enum Keys: String, CodingKey { case starters, subs }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        starters = container.list(LineupPlayer.self, .starters)
        substitutes = container.list(LineupPlayer.self, .subs)
    }

    public init(starters: [LineupPlayer], substitutes: [LineupPlayer] = []) {
        self.starters = starters
        self.substitutes = substitutes
    }

    /// The starters in rows from the goalkeeper to the forwards, for drawing them on a pitch.
    public var rows: [[LineupPlayer]] {
        let groups: [PositionGroup] = [.goalkeeper, .defender, .midfielder, .forward]
        let placed = groups.map { group in starters.filter { $0.group == group } }
        let unplaced = starters.filter { !groups.contains($0.group) }
        return (placed + [unplaced]).filter { !$0.isEmpty }
    }

    /// `4-3-3`, counted from the position names, or nil when the starters are not eleven with a goalkeeper.
    public var formation: String? {
        guard starters.count == 11 else { return nil }
        let count = { (group: PositionGroup) in starters.filter { $0.group == group }.count }
        guard count(.goalkeeper) == 1 else { return nil }
        let line = [count(.defender), count(.midfielder), count(.forward)]
        return line.reduce(0, +) == 10 ? line.map(String.init).joined(separator: "-") : nil
    }
}

/// The teams of a match. Not available for every match: smaller competitions often have none.
public struct Lineup: Sendable, Equatable, Hashable {
    public var home: TeamLineup
    public var away: TeamLineup

    public init(home: TeamLineup, away: TeamLineup) {
        self.home = home
        self.away = away
    }
}

public struct TeamStats: Sendable, Equatable, Hashable, Decodable {
    public var shots: Int?
    public var shotsOnTarget: Int?
    public var shotsOffTarget: Int?
    public var fouls: Int?
    public var passes: Int?
    public var passAccuracy: Int?
    public var tackles: Int?
    public var tackleSuccess: Int?
    public var saves: Int?
    public var yellowCards: Int?
    public var redCards: Int?

    private enum Keys: String, CodingKey {
        case shots, fouls, tackles, saves
        case shotsOnTarget = "shots_on_target", shotsOffTarget = "shots_off_target"
        case passes = "total_passes", passAccuracy = "pass_accuracy", tackleSuccess = "tackle_success"
        case yellowCards = "yellow_cards", redCards = "red_cards"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        shots = container.int(.shots)
        shotsOnTarget = container.int(.shotsOnTarget)
        shotsOffTarget = container.int(.shotsOffTarget)
        fouls = container.int(.fouls)
        passes = container.int(.passes)
        passAccuracy = container.int(.passAccuracy)
        tackles = container.int(.tackles)
        tackleSuccess = container.int(.tackleSuccess)
        saves = container.int(.saves)
        yellowCards = container.int(.yellowCards)
        redCards = container.int(.redCards)
    }
}

public struct MatchStats: Sendable, Equatable, Hashable {
    public var home: TeamStats
    public var away: TeamStats
}
