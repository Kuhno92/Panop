import Foundation
import PanopSports

/// How a match says where it is, in the words of the person's language.
enum MatchText {
    /// The short status: the minute while it is played, "FT" when it is over, the kick-off time before.
    static func status(_ fixture: Fixture) -> String {
        switch fixture.status {
        case .live: fixture.minute ?? String(localized: "LIVE")
        case .halfTime: String(localized: "HT")
        case .finished: String(localized: "FT")
        case .afterExtraTime: String(localized: "AET")
        case .penalties: String(localized: "Pens")
        case .cancelled: String(localized: "Cancelled")
        case .postponed: String(localized: "Postponed")
        case .scheduled: kickoff(fixture)
        case .unknown: fixture.minute ?? kickoff(fixture)
        }
    }

    static func kickoff(_ fixture: Fixture) -> String {
        fixture.kickoff?.formatted(date: .omitted, time: .shortened) ?? "–"
    }

    static func score(_ goals: Int?) -> String {
        goals.map(String.init) ?? "–"
    }

    /// "Norwich 0, Southampton 1, 79th minute", for VoiceOver.
    static func spoken(_ fixture: Fixture) -> String {
        let teams = "\(fixture.homeName) \(String(localized: "versus")) \(fixture.awayName)"
        if fixture.hasScore {
            return "\(teams), \(score(fixture.homeScore)) \(String(localized: "to")) \(score(fixture.awayScore)), \(status(fixture))"
        }
        return "\(teams), \(status(fixture))"
    }

    static func updated(_ date: Date?) -> String? {
        date.map { String(localized: "Updated \($0.formatted(date: .omitted, time: .shortened))") }
    }
}
