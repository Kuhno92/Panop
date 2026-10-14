import Foundation

/// The names one club goes by in guides and in the sports service, as groups: everything in a group is the same team.
/// It is data, and it grows from real guides: a club a guide writes in a way nobody foresaw is one line here.
///
/// Each entry is read the way a text is (see ``TeamNames/tokens(_:)``), so accents and "ue" for "ü" need no entry of
/// their own. Leave out a name that is another club's too ("Paris" is Paris FC as well as Paris Saint-Germain).
enum TeamAliases {
    static let teams: [[String]] = [
        // England
        ["Manchester United", "Man Utd", "Man United", "Manchester Utd", "Man U"],
        ["Manchester City", "Man City"],
        ["Tottenham Hotspur", "Tottenham", "Spurs"],
        ["Wolverhampton Wanderers", "Wolverhampton", "Wolves"],
        ["Newcastle United", "Newcastle", "Newcastle Utd"],
        ["West Ham United", "West Ham"],
        ["Brighton & Hove Albion", "Brighton"],
        ["Nottingham Forest", "Nottm Forest", "Nott'm Forest"],
        ["Leicester City", "Leicester"],
        ["Leeds United", "Leeds"],
        ["Aston Villa", "Villa"],
        ["Crystal Palace"],
        ["Sheffield United", "Sheff Utd"],
        ["AFC Bournemouth", "Bournemouth"],
        // Germany
        ["FC Bayern München", "Bayern Munich", "Bayern Munchen", "Bayern", "FC Bayern", "Bayern Muenchen"],
        ["Borussia Dortmund", "Dortmund", "BVB"],
        ["Bayer 04 Leverkusen", "Bayer Leverkusen", "Leverkusen"],
        ["RB Leipzig", "Leipzig", "Rasenballsport Leipzig"],
        ["Borussia Mönchengladbach", "Gladbach", "Monchengladbach", "M'gladbach", "Borussia Moenchengladbach"],
        ["Eintracht Frankfurt", "Frankfurt", "Eintracht"],
        ["VfB Stuttgart", "Stuttgart"],
        ["VfL Wolfsburg", "Wolfsburg"],
        ["SC Freiburg", "Freiburg"],
        ["1. FC Köln", "FC Köln", "Köln", "Cologne", "Koeln"],
        ["1. FC Union Berlin", "Union Berlin"],
        ["Hertha BSC", "Hertha Berlin", "Hertha"],
        ["Werder Bremen", "Bremen", "Werder"],
        ["1. FSV Mainz 05", "Mainz 05", "Mainz"],
        ["FC Augsburg", "Augsburg"],
        ["TSG Hoffenheim", "TSG 1899 Hoffenheim", "Hoffenheim"],
        ["FC St. Pauli", "St. Pauli", "Sankt Pauli"],
        ["Hamburger SV", "HSV", "Hamburg"],
        ["FC Schalke 04", "Schalke 04", "Schalke"],
        ["1. FC Heidenheim", "Heidenheim"],
        // Spain
        ["Real Madrid", "Real Madrid CF"],
        ["FC Barcelona", "Barcelona", "Barça", "Barca"],
        ["Atlético Madrid", "Atletico Madrid", "Atlético de Madrid", "Atletico", "Atleti"],
        ["Athletic Club", "Athletic Bilbao", "Athletic Club Bilbao"],
        ["Real Sociedad", "Sociedad"],
        ["Sevilla FC", "Sevilla"],
        ["Real Betis", "Betis"],
        ["Villarreal CF", "Villarreal"],
        ["Valencia CF", "Valencia"],
        ["Celta Vigo", "Celta de Vigo", "Celta"],
        // Italy
        ["Juventus", "Juve", "Juventus Turin", "Juventus FC"],
        ["Inter", "Internazionale", "Inter Milan", "Inter Mailand", "Inter Milano"],
        ["AC Milan", "Milan", "AC Mailand"],
        ["SSC Napoli", "Napoli"],
        ["AS Roma", "Roma"],
        ["SS Lazio", "Lazio"],
        ["Atalanta", "Atalanta Bergamo"],
        ["ACF Fiorentina", "Fiorentina"],
        // France
        ["Paris Saint-Germain", "Paris Saint Germain", "PSG", "Paris SG"],
        ["Olympique Marseille", "Olympique de Marseille", "Marseille"],
        ["Olympique Lyonnais", "Olympique Lyon", "Lyon"],
        ["AS Monaco", "Monaco"],
        ["LOSC Lille", "Lille"],
        ["OGC Nice", "Nice"],
        // Elsewhere
        ["AFC Ajax", "Ajax", "Ajax Amsterdam"],
        ["PSV Eindhoven", "PSV"],
        ["Feyenoord", "Feyenoord Rotterdam"],
        ["SL Benfica", "Benfica", "Benfica Lisbon", "Benfica Lissabon"],
        ["FC Porto", "Porto"],
        ["Sporting CP", "Sporting Lisbon", "Sporting Lissabon", "Sporting Clube de Portugal"],
        ["Celtic", "Celtic Glasgow"],
        ["Galatasaray", "Galatasaray Istanbul"],
        ["Fenerbahçe", "Fenerbahce", "Fenerbahce Istanbul"],
        ["Beşiktaş", "Besiktas", "Besiktas Istanbul"],
        ["Red Bull Salzburg", "RB Salzburg", "Salzburg"],
        ["BSC Young Boys", "Young Boys", "Young Boys Bern"]
    ]

    /// Leagues and cups, the same way.
    static let leagues: [[String]] = [
        ["Premier League", "English Premier League", "EPL", "Barclays Premier League"],
        ["Bundesliga", "1. Bundesliga", "German Bundesliga", "Fußball Bundesliga"],
        ["2. Bundesliga", "Zweite Bundesliga"],
        ["La Liga", "LaLiga", "Primera División", "Spanish La Liga", "LaLiga EA Sports"],
        ["Serie A", "Italian Serie A"],
        ["Ligue 1", "French Ligue 1"],
        ["UEFA Champions League", "Champions League", "UCL"],
        ["UEFA Europa League", "Europa League", "UEL"],
        ["UEFA Conference League", "Conference League"],
        ["DFB-Pokal", "DFB Pokal", "German Cup"],
        ["FA Cup"],
        ["EFL Cup", "Carabao Cup", "League Cup"],
        ["Major League Soccer", "MLS"],
        ["Eredivisie"],
        ["Primeira Liga", "Liga Portugal"],
        ["Süper Lig", "Super Lig"],
        ["Scottish Premiership"]
    ]

    /// An entry's words, and the group each team name is in, keyed by its identifying words.
    private static let teamIndex: [String: Int] = index(teams)
    private static let teamPhrases: [[[String]]] = teams.map { $0.map(TeamNames.tokens) }
    private static let leaguePhraseGroups: [[[String]]] = leagues.map { $0.map(TeamNames.tokens) }

    private static func index(_ groups: [[String]]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (number, group) in groups.enumerated() {
            for name in group {
                let key = TeamNames.core(name).joined(separator: " ")
                if !key.isEmpty, result[key] == nil {
                    result[key] = number
                }
            }
        }
        return result
    }

    /// Everything the table knows the same team by, for any of these (already reduced) names.
    static func phrases(forCores cores: [[String]]) -> [[String]] {
        var result: [[String]] = []
        for core in cores {
            guard let group = teamIndex[core.joined(separator: " ")] else { continue }
            for phrase in teamPhrases[group] where !phrase.isEmpty && !result.contains(phrase) {
                result.append(phrase)
            }
        }
        return result
    }

    /// Every name of the leagues whose name appears in `tokens`: "US Major League Soccer" has "Major League Soccer".
    static func leaguePhrases(containedIn tokens: [String]) -> [[String]] {
        var result: [[String]] = []
        for group in leaguePhraseGroups where group.contains(where: { TeamNames.range(of: $0, in: tokens) != nil }) {
            for phrase in group where !phrase.isEmpty && !result.contains(phrase) {
                result.append(phrase)
            }
        }
        return result
    }
}
