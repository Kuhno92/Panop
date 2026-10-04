import Foundation

/// Where Simkl keeps the artwork its list files name. A file gives a path such as `19/19818287730a769e81`;
/// the picture is at `simkl.in/fanart/<path>_w.webp`, a wide image of about 75 KB, which is what a hero needs.
public enum SimklArtwork {
    public static func fanartURL(_ path: String) -> URL? {
        guard !path.isEmpty, !path.contains(".."), !path.hasPrefix("/") else { return nil }
        return URL(string: "https://simkl.in/fanart/\(path)_w.webp")
    }
}
