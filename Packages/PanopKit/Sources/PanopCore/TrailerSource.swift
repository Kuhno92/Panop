import Foundation

/// What a provider means by a film's "trailer", which it writes in several ways: a bare YouTube id, a YouTube address
/// in any of
/// its forms, a link to a video file, or just a web page. Each is played (or opened) differently, so this says which it
/// is.
public enum TrailerSource: Equatable, Sendable {
    /// A YouTube video, by its eleven-character id.
    case youtube(id: String)
    /// A video file or stream a player can open itself: MP4, M4V, MOV or HLS.
    case media(URL)
    /// Any other web page: the browser's to open.
    case web(URL)

    private static let youtubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com",
        "www.youtube-nocookie.com", "youtu.be", "www.youtu.be"
    ]

    private static let mediaExtensions: Set<String> = ["mp4", "m4v", "mov", "m3u8"]

    public init?(_ text: String?) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        // A bare id, as the panel writes it.
        if Self.isVideoID(text) {
            self = .youtube(id: text)
            return
        }
        // An address with the scheme left off: `youtube.com/watch?v=...`, `youtu.be/...`.
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased()
        else { return nil }
        if Self.youtubeHosts.contains(host) {
            if let id = Self.videoID(in: url, host: host) {
                self = .youtube(id: id)
            } else {
                // A channel, a playlist, the front page: no one video to play.
                self = .web(url)
            }
            return
        }
        if Self.mediaExtensions.contains(url.pathExtension.lowercased()) {
            self = .media(url)
        } else {
            self = .web(url)
        }
    }

    /// YouTube's ids are eleven characters of letters, digits, `-` and `_`.
    public static func isVideoID(_ text: String) -> Bool {
        text.count == 11 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static func videoID(in url: URL, host: String) -> String? {
        if host.hasSuffix("youtu.be") {
            return url.pathComponents.dropFirst().first.flatMap { isVideoID($0) ? $0 : nil }
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let id = components?.queryItems?.first(where: { $0.name == "v" })?.value, isVideoID(id) {
            return id
        }
        // `/embed/ID`, `/shorts/ID`, `/live/ID`, `/v/ID`.
        let path = url.pathComponents.filter { $0 != "/" }
        if path.count >= 2, ["embed", "shorts", "live", "v"].contains(path[0]), isVideoID(path[1]) {
            return path[1]
        }
        return nil
    }
}
