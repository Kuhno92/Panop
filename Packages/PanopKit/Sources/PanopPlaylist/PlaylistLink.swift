import Foundation

/// What a pasted playlist address turns out to be, before and after it is fetched.
public enum PlaylistLink {
    /// Whether an address is one of GitHub's own pages (`https://github.com/owner/repo/blob/master/streams/de.m3u`),
    /// which is what a person copies from the address bar. That is an HTML page with the file's text inside it, not the
    /// file: the file is at `raw.githubusercontent.com` (the page's Raw button), and `github.com/.../raw/...`, which
    /// leads there, is fine.
    public static func isGitHubPage(_ text: String) -> Bool {
        guard let components = URLComponents(string: text),
              let host = components.host?.lowercased(),
              host == "github.com" || host == "www.github.com"
        else { return false }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        return !(parts.count >= 3 && parts[2] == "raw")
    }

    /// Whether the start of a download is a web page (or other markup) and not a playlist: a link to a page about a
    /// playlist, a login page, a "not found" page served with a success status. A playlist starts with `#EXTM3U` or,
    /// at the least, with a comment or an address.
    public static func looksLikeWebPage(_ head: Data) -> Bool {
        let text = (String(bytes: head.prefix(2048), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        guard !text.isEmpty, !text.hasPrefix("#EXTM3U") else { return false }
        if text.hasPrefix("<") {
            return true
        }
        let lowered = text.lowercased()
        return lowered.contains("<!doctype html") || lowered.contains("<html")
    }
}
