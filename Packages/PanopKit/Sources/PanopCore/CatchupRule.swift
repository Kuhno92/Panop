import Foundation

/// How an M3U playlist's channel is played from the provider's archive: the `catchup` type and the `catchup-source`
/// template of its `#EXTINF` line, which differ from one provider to the next.
///
/// Kept as plain text in the catalog (``encoded``), so the app stores one string and the portable core decides what it
/// means. A template can carry the account's login, so it is not saved anywhere the stream address is not.
public struct CatchupRule: Sendable, Equatable, Hashable {
    public enum Mode: String, Sendable {
        /// `catchup-source` is the whole address, with placeholders.
        case `default`
        /// `catchup-source` is added to the live address.
        case append
        /// The live address with `utc` and `lutc` query values.
        case shift
        /// Flussonic's archive address, made from the live one.
        case flussonic
        /// The Xtream Codes timeshift address, made from a live address of its form.
        case xtream
    }

    public var mode: Mode
    public var source: String?

    public init(mode: Mode, source: String? = nil) {
        self.mode = mode
        self.source = source
    }

    /// From the attributes of a playlist line. Nil when the line names no way the core knows.
    public init?(type: String?, source: String?) {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let name = type?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let mode: Mode
        switch name {
        case "default": mode = .default
        case "append": mode = .append
        case "shift", "timeshift": mode = .shift
        case "flussonic", "flussonic-hls", "flussonic-ts", "fs": mode = .flussonic
        case "xc", "xtream": mode = .xtream
        // A source with no type is how some lists write the `default` form.
        case "" where given != nil: mode = .default
        default: return nil
        }
        // A form that is nothing without its template.
        if mode == .default || mode == .append, given == nil {
            return nil
        }
        self.init(mode: mode, source: mode == .shift || mode == .flussonic || mode == .xtream ? nil : given)
    }

    // MARK: - Saving

    /// One line: the mode, a newline, the template.
    public var encoded: String {
        mode.rawValue + "\n" + (source ?? "")
    }

    public init?(encoded: String?) {
        guard let encoded, let split = encoded.firstIndex(of: "\n"),
              let mode = Mode(rawValue: String(encoded[..<split]))
        else { return nil }
        let rest = String(encoded[encoded.index(after: split)...])
        self.init(mode: mode, source: rest.isEmpty ? nil : rest)
    }

    // MARK: - The address

    /// Where the programme from `start` to `end` plays from, given the channel's live address.
    ///
    /// `now` is the moment of asking, which some templates carry. Nil when the live address does not have the form the
    /// mode needs.
    public func url(live: String, start: Date, end: Date, now: Date = .now) -> URL? {
        let text: String?
        switch mode {
        case .default:
            text = source.map { Self.fill($0, start: start, end: end, now: now) }
        case .append:
            text = source.map { live + Self.fill($0, start: start, end: end, now: now) }
        case .shift:
            let joiner = live.contains("?") ? "&" : "?"
            text = live + joiner + "utc=\(Int(start.timeIntervalSince1970))&lutc=\(Int(now.timeIntervalSince1970))"
        case .flussonic:
            text = Self.flussonic(live: live, start: start, end: end)
        case .xtream:
            text = Self.xtream(live: live, start: start, end: end)
        }
        return text.flatMap { URL(string: $0) }
    }

    /// The placeholders of the common templates: `{utc}` and `{start}` (the programme's start, in Unix seconds),
    /// `{utcend}` and `{end}`, `{lutc}`, `{now}` and `{timestamp}` (the moment of asking), `{duration}` and `{offset}`
    /// (seconds), and the start's date and time in UTC as `{Y}{m}{d}{H}{M}{S}`. Written with or without a `$` before
    /// the
    /// brace.
    static func fill(_ template: String, start: Date, end: Date, now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        func two(_ value: Int?) -> String {
            String(format: "%02d", value ?? 0)
        }
        let values: [String: String] = [
            "utc": String(Int(start.timeIntervalSince1970)),
            "start": String(Int(start.timeIntervalSince1970)),
            "utcend": String(Int(end.timeIntervalSince1970)),
            "end": String(Int(end.timeIntervalSince1970)),
            "lutc": String(Int(now.timeIntervalSince1970)),
            "now": String(Int(now.timeIntervalSince1970)),
            "timestamp": String(Int(now.timeIntervalSince1970)),
            "duration": String(max(Int(end.timeIntervalSince(start)), 1)),
            "offset": String(max(Int(now.timeIntervalSince(start)), 0)),
            "Y": String(format: "%04d", parts.year ?? 0),
            "m": two(parts.month),
            "d": two(parts.day),
            "H": two(parts.hour),
            "M": two(parts.minute),
            "S": two(parts.second)
        ]
        var result = template
        for (name, value) in values {
            result = result.replacingOccurrences(of: "${\(name)}", with: value)
                .replacingOccurrences(of: "{\(name)}", with: value)
        }
        return result
    }

    /// `http://host/channel/index.m3u8` (or `mpegts`) becomes `http://host/channel/archive-<utc>-<seconds>.m3u8` (or
    /// `.ts`).
    private static func flussonic(live: String, start: Date, end: Date) -> String? {
        guard var components = URLComponents(string: live), components.host != nil else { return nil }
        var segments = components.path.split(separator: "/").map(String.init)
        guard let last = segments.popLast() else { return nil }
        let fileExtension = last.lowercased().hasSuffix("m3u8") ? "m3u8" : "ts"
        let seconds = max(Int(end.timeIntervalSince(start)), 1)
        // A stream address ending in the stream's own name has no file in it: that name is the channel.
        if !last.contains("."), last != "mpegts" {
            segments.append(last)
        }
        segments.append("archive-\(Int(start.timeIntervalSince1970))-\(seconds).\(fileExtension)")
        components.path = "/" + segments.joined(separator: "/")
        return components.string
    }

    /// `http://host/user/pass/123`, `.../live/user/pass/123.ts` and the like become the panel's timeshift address. The
    /// panel's own time zone is not known from a playlist, so the start is written in UTC.
    private static func xtream(live: String, start: Date, end: Date) -> String? {
        guard var components = URLComponents(string: live), components.host != nil else { return nil }
        var segments = components.path.split(separator: "/").map(String.init)
        guard let file = segments.popLast() else { return nil }
        let id = file.split(separator: ".").first.map(String.init) ?? file
        guard segments.count >= 2, !id.isEmpty else { return nil }
        let password = segments.removeLast()
        let user = segments.removeLast()
        if segments.last == "live" {
            segments.removeLast()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd:HH-mm"
        let minutes = max(Int((end.timeIntervalSince(start) / 60).rounded(.up)), 1)
        components.path = "/" + (segments + [
            "timeshift",
            user,
            password,
            String(minutes),
            formatter.string(from: start),
            "\(id).ts"
        ])
        .joined(separator: "/")
        return components.string
    }
}
