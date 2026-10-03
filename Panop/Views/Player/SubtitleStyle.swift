import Foundation

/// How subtitles look: size, colour, the box behind them, and how high they sit.
///
/// Kept as one value so it is stored as one setting and a preview and the player read the same thing.
nonisolated struct RGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

nonisolated struct SubtitleStyle: Equatable, Sendable, RawRepresentable {
    enum Size: String, CaseIterable, Codable, Identifiable, Sendable {
        case small, medium, large, extraLarge

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .small: String(localized: "Small")
            case .medium: String(localized: "Medium")
            case .large: String(localized: "Large")
            case .extraLarge: String(localized: "Extra large")
            }
        }

        /// Relative to the standard size.
        var scale: Double {
            switch self {
            case .small: 0.8
            case .medium: 1
            case .large: 1.3
            case .extraLarge: 1.7
            }
        }
    }

    enum Tint: String, CaseIterable, Codable, Identifiable, Sendable {
        case white, yellow, cyan, green

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .white: String(localized: "White")
            case .yellow: String(localized: "Yellow")
            case .cyan: String(localized: "Cyan")
            case .green: String(localized: "Green")
            }
        }

        /// Red, green and blue, 0 to 1.
        var components: RGB {
            switch self {
            case .white: RGB(red: 1, green: 1, blue: 1)
            case .yellow: RGB(red: 1, green: 0.9, blue: 0.2)
            case .cyan: RGB(red: 0.3, green: 0.9, blue: 1)
            case .green: RGB(red: 0.4, green: 1, blue: 0.5)
            }
        }
    }

    enum Backdrop: String, CaseIterable, Codable, Identifiable, Sendable {
        case none, translucent, solid

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .none: String(localized: "None")
            case .translucent: String(localized: "Translucent")
            case .solid: String(localized: "Solid")
            }
        }

        var opacity: Double {
            switch self {
            case .none: 0
            case .translucent: 0.6
            case .solid: 1
            }
        }
    }

    var size = Size.medium
    var tint = Tint.white
    var backdrop = Backdrop.translucent
    /// Higher on the screen, clear of a station logo or a ticker at the bottom.
    var raised = false

    static let standard = SubtitleStyle()
    static let key = "subtitleStyle"

    /// Whether the person changed anything. Until they do, a player that has its own system setting for
    /// captions (AVPlayer) keeps following it.
    var isCustomised: Bool {
        self != Self.standard
    }

    /// What is saved now.
    static var current: SubtitleStyle {
        UserDefaults.standard.string(forKey: key).flatMap(SubtitleStyle.init(rawValue:)) ?? .standard
    }

    // MARK: RawRepresentable, so one `@AppStorage` holds the lot

    init() {}

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredSubtitleStyle.self, from: data) else { return nil }
        size = stored.size
        tint = stored.tint
        backdrop = stored.backdrop
        raised = stored.raised
    }

    var rawValue: String {
        let stored = StoredSubtitleStyle(size: size, tint: tint, backdrop: backdrop, raised: raised)
        // Sorted, so the same style is always the same text: that text is what `@AppStorage` compares.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(stored) else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

/// What is written down. Apart from `SubtitleStyle` because a type that is both `RawRepresentable` and
/// `Codable` encodes itself through its raw value, which encodes itself, without end. A field a later
/// version adds, or a value it no longer knows, falls back to the standard look instead of losing the lot.
nonisolated struct StoredSubtitleStyle: Codable {
    var size: SubtitleStyle.Size
    var tint: SubtitleStyle.Tint
    var backdrop: SubtitleStyle.Backdrop
    var raised: Bool

    init(size: SubtitleStyle.Size, tint: SubtitleStyle.Tint, backdrop: SubtitleStyle.Backdrop, raised: Bool) {
        self.size = size
        self.tint = tint
        self.backdrop = backdrop
        self.raised = raised
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = (try? container.decodeIfPresent(SubtitleStyle.Size.self, forKey: .size)) ?? .medium
        tint = (try? container.decodeIfPresent(SubtitleStyle.Tint.self, forKey: .tint)) ?? .white
        backdrop = (try? container.decodeIfPresent(SubtitleStyle.Backdrop.self, forKey: .backdrop)) ?? .translucent
        raised = (try? container.decodeIfPresent(Bool.self, forKey: .raised)) ?? false
    }
}
