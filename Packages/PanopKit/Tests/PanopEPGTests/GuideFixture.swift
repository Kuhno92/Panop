import Foundation

/// A deterministic XMLTV guide, and the same guide gzip-compressed by zlib.
///
/// The compressed form was produced by an independent encoder, so tests that
/// read it prove the decoder against real gzip and not against itself.
enum GuideFixture {
    /// One channel and `programmes` programmes, one minute each from 00:00 UTC.
    static func xml(programmes: Int) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<tv generator-info-name="test">"#,
            #"<channel id="ard.de"><display-name>Das Erste</display-name></channel>"#
        ]
        for index in 0 ..< programmes {
            let start = String(format: "%02d%02d00", (index / 60) % 24, index % 60)
            let stop = String(format: "%02d%02d00", ((index + 1) / 60) % 24, (index + 1) % 60)
            lines.append(
                #"<programme start="20260929\#(start) +0000" stop="20260929\#(stop) +0000" channel="ard.de">"#
                    + "<title>Show \(index)</title><desc>Description of show \(index)</desc></programme>"
            )
        }
        lines.append("</tv>")
        return lines.joined(separator: "\n")
    }

    /// `xml(programmes: 120)` compressed with zlib at level 9.
    static let gzipped120: Data = {
        let text = """
        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
        """
        return Data(base64Encoded: text.filter { !$0.isWhitespace }) ?? Data()
    }()
}
