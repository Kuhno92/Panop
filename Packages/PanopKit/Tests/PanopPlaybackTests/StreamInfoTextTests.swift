import PanopPlayback
import Testing

struct StreamInfoTextTests {
    @Test func `a typical IPTV channel reads as one line`() {
        let info = StreamInfo(
            container: "mpegts", videoCodec: "h264", width: 1920, height: 1080, frameRate: 50,
            audioCodec: "ac3", audioChannels: 6
        )
        #expect(StreamInfoText.summary(info) == "MPEG-TS · 1080p50 · H.264 · Dolby Digital 5.1")
    }

    @Test func `HDR and Atmos are named when the engine knows`() {
        let info = StreamInfo(
            container: "matroska,webm", videoCodec: "hevc", width: 3840, height: 2160, frameRate: 24,
            hdr: "HDR10", audioCodec: "eac3", audioChannels: 6, audioIsAtmos: true
        )
        #expect(StreamInfoText.summary(info) == "MKV · 4K · HEVC · HDR10 · Dolby Atmos 5.1")
    }

    @Test(arguments: [
        ("hls,applehttp", "HLS"), ("mov,mp4,m4a,3gp,3g2,mj2", "MP4"), ("mpegts", "MPEG-TS"),
        ("matroska,webm", "MKV"), ("dash", "DASH"), ("flv", "FLV")
    ])
    func `containers read as people say them`(raw: String, label: String) {
        #expect(StreamInfoText.container(raw) == label)
    }

    @Test func `an unknown container says nothing rather than something wrong`() {
        #expect(StreamInfoText.container("rtsp") == nil)
        #expect(StreamInfoText.container(nil) == nil)
    }

    @Test(arguments: [
        (1920, 1080, 25.0, "1080p"), (1920, 800, 24.0, "1080p"), (1280, 720, 50.0, "720p50"),
        (3840, 2160, 60.0, "4K60"), (720, 576, 25.0, "576p"), (1024, 576, 25.0, "576p"), (2560, 1440, 30.0, "1440p")
    ])
    func `a picture is named by its class`(width: Int, height: Int, rate: Double, label: String) {
        #expect(StreamInfoText.resolution(width: width, height: height, frameRate: rate) == label)
    }

    @Test func `no size says nothing`() {
        #expect(StreamInfoText.resolution(width: nil, height: nil, frameRate: 25) == nil)
        #expect(StreamInfoText.resolution(width: 0, height: 0, frameRate: 25) == nil)
    }

    @Test(arguments: [("hvc1", "HEVC"), ("avc1", "H.264"), ("mpeg2video", "MPEG-2"), ("av01", "AV1"), ("dvh1", "HEVC")])
    func `video codecs`(raw: String, label: String) {
        #expect(StreamInfoText.videoCodec(raw) == label)
    }

    @Test(arguments: [
        ("aac", 2, "AAC Stereo"), ("ec-3", 6, "Dolby Digital Plus 5.1"), ("dts", 6, "DTS 5.1"),
        ("truehd", 8, "Dolby TrueHD 7.1"), ("mp2", 2, "MP2 Stereo"), ("mp3", 1, "MP3 Mono")
    ])
    func `sound reads as codec and layout`(codec: String, channels: Int, label: String) {
        #expect(StreamInfoText.sound(codec: codec, channels: channels) == label)
    }

    @Test func `an engine that knows nothing shows nothing`() {
        #expect(StreamInfoText.summary(StreamInfo()) == nil)
        #expect(StreamInfo().isEmpty)
    }

    @Test func `the address can hint at the container`() {
        #expect(StreamInfoText.containerHint(address: "http://h/live/a.m3u8?token=1") == "hls")
        #expect(StreamInfoText.containerHint(address: "http://h/live/1234.ts") == "mpegts")
        #expect(StreamInfoText.containerHint(address: "http://h/movie/u/p/55.mkv") == "matroska")
        #expect(StreamInfoText.containerHint(address: "http://h/live/u/p/1234") == nil)
    }
}
