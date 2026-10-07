import Foundation
@testable import PanopPlaylist
import Testing

@Suite("Playlist links")
struct PlaylistLinkTests {
    @Test
    func `the pages GitHub itself serves are recognised`() {
        for address in [
            "https://github.com/iptv-org/iptv/blob/master/streams/de.m3u",
            "https://www.github.com/o/r/blob/main/a/b/c.m3u8",
            "https://github.com/iptv-org/iptv",
            "http://GitHub.com/iptv-org/iptv/tree/master/streams"
        ] {
            #expect(PlaylistLink.isGitHubPage(address), "\(address)")
        }
    }

    @Test
    func `the file's own address is not a GitHub page`() {
        for address in [
            "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/de.m3u",
            "https://github.com/iptv-org/iptv/raw/master/streams/de.m3u",
            "http://provider.example:8080/get.php?username=u&password=p&type=m3u",
            "https://example.com/github.com/playlist.m3u",
            "not an address"
        ] {
            #expect(!PlaylistLink.isGitHubPage(address), "\(address)")
        }
    }

    @Test
    func `a web page is not a playlist, a playlist is`() {
        #expect(PlaylistLink.looksLikeWebPage(Data("<!DOCTYPE html>\n<html lang=\"en\">".utf8)))
        #expect(PlaylistLink.looksLikeWebPage(Data("  \n<html><body>Not found</body></html>".utf8)))
        #expect(!PlaylistLink.looksLikeWebPage(Data("#EXTM3U\n#EXTINF:-1,Das Erste\nhttp://h/1.ts\n".utf8)))
        #expect(!PlaylistLink.looksLikeWebPage(Data("\u{FEFF}#EXTM3U\n".utf8)))
        #expect(!PlaylistLink.looksLikeWebPage(Data("http://h/1.ts\nhttp://h/2.ts\n".utf8)))
        #expect(!PlaylistLink.looksLikeWebPage(Data()), "an empty file is another kind of problem")
    }
}
