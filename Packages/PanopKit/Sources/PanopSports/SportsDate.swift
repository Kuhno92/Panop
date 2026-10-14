import Foundation

public enum SportsDate {
    /// The service's UTC time stamps (`2026-10-14T18:45:00Z`), with or without fractions of a second.
    public static func parse(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// The day key the service's day call wants (`2026-10-14`) for a moment, in a time zone.
    public static func dayKey(for date: Date, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Where the service keeps its team logos. They are plain files at a public address, which need no key and so cost
/// no request of the daily budget.
public enum SportsLogo {
    public static let base = "https://sportapi.ai/logos/"

    public static func url(file: String?) -> URL? {
        guard let file, !file.isEmpty,
              let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: base + encoded)
    }
}
