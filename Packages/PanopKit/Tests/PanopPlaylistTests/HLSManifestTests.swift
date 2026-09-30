import Foundation
@testable import PanopPlaylist
import Testing

private func kind(_ text: String) -> HLSManifest.Kind? {
    HLSManifest.kind(ofPrefix: Data(text.utf8))
}

@Suite("HLS manifest detection")
struct HLSManifestTests {
    /// The structure of a real multivariant playlist (an Akamai-hosted broadcaster's): separate
    /// audio groups, redundant variants, and relative variant paths.
    @Test
    func `a multivariant playlist is HLS`() {
        let multivariant = """
        #EXTM3U

        #EXT-X-INDEPENDENT-SEGMENTS

        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="A1",NAME="TV Ton",LANGUAGE="deu",DEFAULT=YES,URI="/hls/live/1/4.m3u8"
        #EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=1173371,AUDIO="A1",RESOLUTION=640x360
        /hls/live/1/1.m3u8
        """
        #expect(kind(multivariant) == .live)
    }

    @Test
    func `a live media playlist is HLS and live`() {
        let media = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:100\n#EXTINF:6.0,\nseg100.ts\n"
        #expect(kind(media) == .live)
    }

    @Test
    func `a finished media playlist is on demand`() {
        let vod = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6.0,\na.ts\n#EXTINF:6.0,\nb.ts\n#EXT-X-ENDLIST\n"
        #expect(kind(vod) == .onDemand)
    }

    /// The whole reason this exists: IPTV playlists must never be mistaken for HLS,
    /// however many channels and attributes they carry.
    @Test
    func `an IPTV playlist is not HLS`() {
        let playlist = """
        #EXTM3U url-tvg="http://epg/guide.xml"
        #EXTVLCOPT:http-user-agent=Mozilla
        #EXTINF:-1 tvg-id="ard.de" tvg-logo="http://img/1.png" group-title="News",Das Erste
        http://host/live/1.ts
        #EXTINF:-1,ZDF
        http://host/live/2.m3u8
        #EXTGRP:Sport
        #EXTINF:-1,Sport 1
        http://host/live/3.ts
        """
        #expect(kind(playlist) == nil)
    }

    @Test(arguments: ["", "not a playlist at all", "<html><body>Forbidden</body></html>", "#EXT-X-TARGETDURATION:6\n"])
    func `text without an EXTM3U header is not HLS`(text: String) {
        #expect(kind(text) == nil)
    }

    @Test
    func `only the start of a large file is read`() {
        // 100 KB of channels, then an HLS tag. The tag is past the window.
        let channels = String(repeating: "#EXTINF:-1,Channel\nhttp://host/x.ts\n", count: 3000)
        #expect(kind("#EXTM3U\n" + channels + "#EXT-X-TARGETDURATION:6\n") == nil)
    }

    @Test
    func `handles CRLF line endings and indentation`() {
        #expect(kind("#EXTM3U\r\n  #EXT-X-STREAM-INF:BANDWIDTH=1\r\nhttp://h/a.m3u8\r\n") == .live)
    }
}
