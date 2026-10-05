import SwiftUI

// What the film and series pages say about a title, and the pieces that say it.

/// One small fact, drawn as a capsule: a rating, a year, a genre.
struct DetailChip: Identifiable, Hashable {
    var text: String
    var symbol: String?
    var tint: Color?

    var id: String {
        text
    }
}

/// Capsules that wrap onto the next line when the row is full, like text.
struct DetailChips: View {
    let chips: [DetailChip]

    var body: some View {
        if !chips.isEmpty {
            WrapLayout(spacing: 6) {
                ForEach(chips) { chip in
                    HStack(spacing: 4) {
                        if let symbol = chip.symbol {
                            Image(systemName: symbol).foregroundStyle(chip.tint ?? .secondary)
                        }
                        Text(chip.text)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.14), in: Capsule())
                    .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}

/// Lays its children out left to right and starts a new line when one does not fit.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(subviews, width: bounds.width)
        for (index, frame) in placed.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}

/// A heading and what follows it, for the cast, the director and the like.
struct DetailFact: View {
    let title: LocalizedStringKey
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// How the panel's raw values read on screen. Pure, so it can be tested.
nonisolated enum DetailFormat {
    /// `2004-09-22`, `2004` or `22/09/2004`, as the panels write it: the year, or nil.
    static func year(from text: String?) -> Int? {
        guard let text else { return nil }
        for match in text.split(whereSeparator: { !$0.isNumber }) where match.count == 4 {
            if let year = Int(match), (1880 ... 2100).contains(year) {
                return year
            }
        }
        return nil
    }

    /// A full date in the person's language when the panel gave one (`2004-09-22`), otherwise what it gave.
    static func date(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        if parts.count == 3, let date = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        {
            return date.formatted(date: .long, time: .omitted)
        }
        return text
    }

    /// `1 h 5 min`, or `45 min`.
    static func runtime(minutes: Int) -> String {
        if minutes >= 60 {
            return String(localized: "\(minutes / 60) h \(minutes % 60) min")
        }
        return String(localized: "\(minutes) min")
    }

    /// A rating out of ten, as `8.4`.
    static func rating(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// The genres the panel lists in one string (`Drama, Mystery`), up to `limit` of them.
    static func genres(_ text: String?, limit: Int = 3) -> [String] {
        guard let text else { return [] }
        return Array(text.split(whereSeparator: { ",/|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(limit))
    }

    /// `1080p · HEVC · AC3`, from what the panel probed. Nil when it did not.
    static func quality(height: Int?, video: String?, audio: String?) -> String? {
        var parts: [String] = []
        if let height, height > 0 {
            parts.append("\(height)p")
        }
        if let video, let name = codec(video) {
            parts.append(name)
        }
        if let audio, let name = codec(audio) {
            parts.append(name)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func codec(_ name: String) -> String? {
        let names = [
            "h264": "H.264", "avc": "H.264", "hevc": "HEVC", "h265": "HEVC", "av1": "AV1", "vp9": "VP9",
            "mpeg2video": "MPEG-2", "aac": "AAC", "ac3": "AC3", "eac3": "E-AC3", "dts": "DTS", "truehd": "TrueHD",
            "mp3": "MP3", "opus": "Opus", "flac": "FLAC"
        ]
        let key = name.lowercased()
        return names[key] ?? (key.isEmpty ? nil : key.uppercased())
    }

    static func seasons(_ count: Int) -> String {
        count == 1 ? String(localized: "1 season") : String(localized: "\(count) seasons")
    }

    static func episodes(_ count: Int) -> String {
        count == 1 ? String(localized: "1 episode") : String(localized: "\(count) episodes")
    }
}
