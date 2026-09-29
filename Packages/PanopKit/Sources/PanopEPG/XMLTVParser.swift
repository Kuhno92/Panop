import Foundation

/// Incremental XMLTV parser. Feed chunks, receive channels and programmes.
///
/// Like ``M3UParser`` in `PanopPlaylist` it does no I/O, which keeps it
/// testable at any chunk size and portable. See ``EPGBatches`` for reading a
/// guide over the network.
///
/// Pass a `window` to keep the guide to what the UI can show. A provider's
/// guide often spans two weeks of every channel, and most of it is never
/// looked at; programmes outside the window are dropped as they are parsed and
/// never reach the database.
public struct XMLTVParser {
    /// Programmes discarded for falling outside `window`.
    public private(set) var programmesOutsideWindow = 0
    /// Programmes discarded because they had no channel, no title or an
    /// unreadable time.
    public private(set) var invalidProgrammes = 0

    private let window: ClosedRange<Date>?
    private var tokenizer = XMLTokenizer()
    private var depth = 0
    private var sawRoot = false
    private var rootClosed = false

    private var channel: EPGChannel?
    private var programme: EPGProgramme?
    private var discardingProgramme = false
    private var episodeSystem: String?
    private var episodeIsOnscreen = false

    private enum Target { case displayName, title, subtitle, description, category, episode }
    private var target: Target?
    private var text = ""
    private var pendingLanguage: String?

    /// Element depths: `<tv>` is 1, `<channel>` and `<programme>` are 2, and
    /// their fields are 3.
    private enum Depth {
        static let root = 1
        static let record = 2
        static let field = 3
    }

    /// A single text field is never legitimately this long.
    private static let maxTextLength = 64 * 1024

    public init(window: ClosedRange<Date>? = nil) {
        self.window = window
    }

    public mutating func consume(_ chunk: Data) throws -> [EPGElement] {
        let events: [XMLTokenizer.Event]
        do {
            events = try tokenizer.consume(chunk)
        } catch {
            throw EPGError.malformed
        }
        var elements: [EPGElement] = []
        for event in events {
            try handle(event, into: &elements)
        }
        return elements
    }

    /// Verifies the document ended cleanly. Call once, after the last chunk.
    public func finish() throws {
        do {
            try tokenizer.finish()
        } catch {
            throw EPGError.truncated
        }
        guard sawRoot else { throw EPGError.notXMLTV }
        guard rootClosed else { throw EPGError.truncated }
    }

    // MARK: - Events

    private mutating func handle(_ event: XMLTokenizer.Event, into elements: inout [EPGElement]) throws {
        switch event {
        case let .start(name, attributes):
            try handleStart(name, attributes)
        case let .end(name):
            handleEnd(name, into: &elements)
        case let .text(value):
            guard target != nil else { return }
            // One event can carry the whole field, so cut it here. Characters
            // are at least a byte each, so the byte cap is never exceeded.
            let room = Self.maxTextLength - text.utf8.count
            // `prefix` walks grapheme clusters, so only pay for it on the rare
            // over-long field.
            if value.utf8.count <= room {
                text += value
            } else if room > 0 {
                text += value.prefix(room)
            }
        }
    }

    private mutating func handleStart(_ name: String, _ attributes: [XMLTokenizer.Attribute]) throws {
        depth += 1

        if depth == Depth.root {
            // Fail on the first element, so an HTML error page is rejected
            // immediately instead of after being read to the end.
            guard name == "tv" else { throw EPGError.notXMLTV }
            sawRoot = true
            return
        }
        guard sawRoot else { throw EPGError.notXMLTV }

        if depth == Depth.record {
            switch name {
            case "channel": beginChannel(attributes)
            case "programme": beginProgramme(attributes)
            default: break
            }
        } else if depth == Depth.field {
            beginField(name, attributes)
        }
    }

    private mutating func handleEnd(_ name: String, into elements: inout [EPGElement]) {
        switch depth {
        case Depth.field:
            commitField()
        case Depth.record:
            if name == "channel", let finished = channel {
                elements.append(.channel(finished))
            } else if name == "programme" {
                finishProgramme(into: &elements)
            }
            channel = nil
            programme = nil
            discardingProgramme = false
        case Depth.root:
            rootClosed = true
        default:
            break
        }
        depth -= 1
    }

    // MARK: - Records

    private mutating func beginChannel(_ attributes: [XMLTokenizer.Attribute]) {
        guard let id = Self.attribute("id", in: attributes), !id.isEmpty else { return }
        channel = EPGChannel(id: id)
    }

    private mutating func beginProgramme(_ attributes: [XMLTokenizer.Attribute]) {
        guard
            let channelID = Self.attribute("channel", in: attributes), !channelID.isEmpty,
            let start = Self.attribute("start", in: attributes).flatMap(XMLTVDate.parse)
        else {
            invalidProgrammes += 1
            discardingProgramme = true
            return
        }
        // `stop` is optional in XMLTV. Reading it as equal to `start` keeps the
        // programme; the catalog can end it where the next one begins.
        let stop = Self.attribute("stop", in: attributes).flatMap(XMLTVDate.parse) ?? start
        programme = EPGProgramme(channelID: channelID, start: start, stop: stop, title: "")
        episodeSystem = nil
        episodeIsOnscreen = false
    }

    private mutating func finishProgramme(into elements: inout [EPGElement]) {
        guard !discardingProgramme, let finished = programme else { return }
        guard !finished.title.isEmpty else {
            invalidProgrammes += 1
            return
        }
        if let window, finished.stop <= window.lowerBound || finished.start > window.upperBound {
            programmesOutsideWindow += 1
            return
        }
        elements.append(.programme(finished))
    }

    // MARK: - Fields

    private mutating func beginField(_ name: String, _ attributes: [XMLTokenizer.Attribute]) {
        target = nil
        text = ""

        if channel != nil {
            switch name {
            case "display-name": target = .displayName
            case "icon" where channel?.iconURL == nil: channel?.iconURL = Self.attribute("src", in: attributes)
            default: break
            }
        } else if programme != nil {
            switch name {
            case "title":
                target = .title
                pendingLanguage = Self.attribute("lang", in: attributes)
            case "sub-title": target = .subtitle
            case "desc": target = .description
            case "category": target = .category
            case "episode-num":
                target = .episode
                episodeSystem = Self.attribute("system", in: attributes)
            case "icon" where programme?.iconURL == nil: programme?.iconURL = Self.attribute("src", in: attributes)
            default: break
            }
        }
    }

    private mutating func commitField() {
        defer {
            target = nil
            text = ""
        }
        guard let target else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        switch target {
        case .displayName:
            channel?.displayNames.append(value)
        case .title:
            // Guides repeat a title per language; the first is the primary.
            if programme?.title.isEmpty == true {
                programme?.title = value
                programme?.language = pendingLanguage
            }
        case .subtitle:
            if programme?.subtitle == nil {
                programme?.subtitle = value
            }
        case .description:
            if programme?.details == nil {
                programme?.details = value
            }
        case .category:
            programme?.categories.append(value)
        case .episode:
            let onscreen = episodeSystem == "onscreen"
            if programme?.episodeNumber == nil || (onscreen && !episodeIsOnscreen) {
                programme?.episodeNumber = value
                episodeIsOnscreen = onscreen
            }
        }
    }

    private static func attribute(_ name: String, in attributes: [XMLTokenizer.Attribute]) -> String? {
        attributes.first { $0.name == name }?.value
    }
}
