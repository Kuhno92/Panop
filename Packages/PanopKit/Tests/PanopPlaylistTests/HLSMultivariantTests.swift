import Foundation
@testable import PanopPlaylist
import Testing

@Suite("HLS multivariant simplification")
struct HLSMultivariantTests {
    private let origin = URL(string: "https://cdn.example/hls/live/2016501/dach/high/master.m3u8")!

    /// The shape of a real broadcaster's playlist: three bitrates on two paths, separate audio
    /// groups per path, subtitles, root-relative addresses and commas inside quoted attributes.
    private let broadcaster = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="A-one",NAME="TV Ton",LANGUAGE="deu",DEFAULT=YES,URI="/hls/live/one/4/4.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="A-one",NAME="Original",LANGUAGE="mul",URI="/hls/live/one/5/5.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="A-two",NAME="TV Ton",LANGUAGE="deu",DEFAULT=YES,URI="/hls/live/two/4/4.m3u8"
    #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="T-one",NAME="Untertitel",LANGUAGE="deu",URI="/hls/live/one/sub/1.m3u8"
    #EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=1173371,AUDIO="A-one",SUBTITLES="T-one",RESOLUTION=640x360
    /hls/live/one/1/1.m3u8
    #EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=1173371,AUDIO="A-two",SUBTITLES="T-one",RESOLUTION=640x360
    /hls/live/two/1/1.m3u8
    #EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=2257198,AUDIO="A-one",SUBTITLES="T-one",RESOLUTION=960x540
    /hls/live/one/2/2.m3u8
    #EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=2257198,AUDIO="A-two",SUBTITLES="T-one",RESOLUTION=960x540
    /hls/live/two/2/2.m3u8
    #EXT-X-STREAM-INF:CODECS="avc1.640028,mp4a.40.2",BANDWIDTH=4504154,AUDIO="A-one",SUBTITLES="T-one",RESOLUTION=1280x720
    /hls/live/one/3/3.m3u8
    #EXT-X-STREAM-INF:CODECS="avc1.640028,mp4a.40.2",BANDWIDTH=4504154,AUDIO="A-two",SUBTITLES="T-one",RESOLUTION=1280x720
    /hls/live/two/3/3.m3u8
    """

    private func variantLines(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { $0.hasPrefix("#EXT-X-STREAM-INF") }
    }

    private func addresses(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
    }

    @Test
    func `the best variant under the cap is the one kept, and only that one`() throws {
        let result = try #require(HLSMultivariant.simplified(broadcaster, base: origin))

        #expect(variantLines(result).count == 1)
        #expect(variantLines(result).first?.contains("BANDWIDTH=4504154") == true)
        #expect(addresses(result) == ["https://cdn.example/hls/live/one/3/3.m3u8"], "the first listed of equals")
    }

    @Test
    func `a lower cap picks a lower variant`() throws {
        let result = try #require(HLSMultivariant.simplified(broadcaster, base: origin, maxBandwidth: 2_500_000))

        #expect(variantLines(result).first?.contains("BANDWIDTH=2257198") == true)
    }

    @Test
    func `when every variant is over the cap the lowest is used, not none`() throws {
        let result = try #require(HLSMultivariant.simplified(broadcaster, base: origin, maxBandwidth: 100))

        #expect(variantLines(result).first?.contains("BANDWIDTH=1173371") == true)
    }

    @Test
    func `only the audio group of the chosen variant is kept`() throws {
        let result = try #require(HLSMultivariant.simplified(broadcaster, base: origin))

        let media = result.split(separator: "\n").filter { $0.hasPrefix("#EXT-X-MEDIA") }
        #expect(media.count == 2, "the two audio entries of the first path")
        #expect(media.allSatisfy { $0.contains("GROUP-ID=\"A-one\"") })
        #expect(!result.contains("A-two"))
    }

    @Test
    func `subtitles are dropped, the variant no longer refers to them`() throws {
        let result = try #require(HLSMultivariant.simplified(broadcaster, base: origin))

        #expect(!result.contains("SUBTITLES"))
        #expect(!result.contains("Untertitel"))
    }

    @Test
    func `every address is absolute, whether it was root-relative, relative or already absolute`() throws {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="x",URI="audio/a.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO="a"
        video/low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2000000,AUDIO="a"
        https://other.example/video/high.m3u8
        """

        let location = URL(fileURLWithPath: "/")
        let page = URL(string: "https://cdn.example/live/index.m3u8", relativeTo: location)?.absoluteURL ?? location
        let result = try #require(HLSMultivariant.simplified(text, base: page))

        #expect(result.contains("URI=\"https://cdn.example/live/audio/a.m3u8\""))
        #expect(addresses(result) == ["https://other.example/video/high.m3u8"])
    }

    @Test
    func `a comma inside a quoted attribute does not split it`() throws {
        let result = try #require(HLSMultivariant.simplified(broadcaster, base: origin))

        #expect(result.contains("CODECS=\"avc1.640028,mp4a.40.2\""), "the codec list stayed in one piece")
        #expect(result.contains("RESOLUTION=1280x720"))
    }

    @Test
    func `a stream whose audio is in its video has no audio entries to keep`() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1000000
        low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=3000000
        high.m3u8
        """

        let result = try #require(HLSMultivariant.simplified(text, base: origin))

        #expect(!result.contains("EXT-X-MEDIA"))
        #expect(addresses(result) == ["https://cdn.example/hls/live/2016501/dach/high/high.m3u8"])
    }

    @Test
    func `there is nothing to simplify in a media playlist or a one-variant playlist`() {
        let media = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6.0,\nseg1.ts\n"
        let single = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000\nonly.m3u8\n"

        #expect(HLSMultivariant.simplified(media, base: origin) == nil)
        #expect(HLSMultivariant.simplified(single, base: origin) == nil)
        #expect(HLSMultivariant.simplified("not a playlist", base: origin) == nil)
        #expect(HLSMultivariant.simplified("", base: origin) == nil)
    }

    @Test
    func `the result is itself a playlist of one variant and is left alone if simplified again`() throws {
        let once = try #require(HLSMultivariant.simplified(broadcaster, base: origin))

        #expect(HLSMultivariant.simplified(once, base: origin) == nil)
        #expect(once.hasPrefix("#EXTM3U"))
    }
}
