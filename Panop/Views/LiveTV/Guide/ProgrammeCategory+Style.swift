import SwiftUI

extension ProgrammeCategory {
    /// A colour for the kind, mid-dark so white text reads on it when it is the programme on air, and so a
    /// light tint of it still reads as its own colour behind dark text. Not the system accent, which is white
    /// on Apple TV.
    var color: Color {
        switch self {
        case .news: Color(red: 0.16, green: 0.42, blue: 0.86)
        case .sport: Color(red: 0.10, green: 0.56, blue: 0.32)
        case .film: Color(red: 0.55, green: 0.30, blue: 0.80)
        case .series: Color(red: 0.07, green: 0.52, blue: 0.58)
        case .kids: Color(red: 0.90, green: 0.45, blue: 0.10)
        case .documentary: Color(red: 0.60, green: 0.42, blue: 0.22)
        case .music: Color(red: 0.82, green: 0.22, blue: 0.48)
        case .entertainment: Color(red: 0.78, green: 0.50, blue: 0.02)
        case .other: Color(red: 0.38, green: 0.40, blue: 0.46)
        }
    }

    var title: String {
        switch self {
        case .news: String(localized: "News")
        case .sport: String(localized: "Sport")
        case .film: String(localized: "Films")
        case .series: String(localized: "Series")
        case .kids: String(localized: "Kids")
        case .documentary: String(localized: "Documentaries")
        case .music: String(localized: "Music")
        case .entertainment: String(localized: "Entertainment")
        case .other: String(localized: "Other")
        }
    }
}
