import PanopCore
@testable import PanopPlayback
import Testing

@Suite("Engine order by kind of stream")
struct EnginePriorityTests {
    private func request(_ address: String, _ kind: MediaKind) -> PlaybackRequest {
        PlaybackRequest(PlaybackItem(url: address, mediaKind: kind))
    }

    @Test
    func `an MP4 film starts with AVPlayer, which plays it`() {
        let order = PlaybackEngineKind.defaultPriority(for: request("http://h/movie/u/p/1.mp4", .movie))
        #expect(order == [.avPlayer, .lumeEngine, .vlcKit, .aetherEngine, .ksPlayer])
    }

    @Test
    func `an MKV film does not start with AVPlayer, which refuses it`() {
        let order = PlaybackEngineKind.defaultPriority(for: request("http://h/movie/u/p/1.mkv", .movie))
        #expect(
            order == [.lumeEngine, .vlcKit, .aetherEngine, .avPlayer, .ksPlayer],
            "AVPlayer is a late resort, not left out"
        )
    }

    @Test
    func `raw transport stream live TV starts with an FFmpeg engine and never offers AetherEngine by itself`() {
        let order = PlaybackEngineKind.defaultPriority(for: request("http://h/live/u/p/1.ts", .live))
        #expect(order.first == .lumeEngine)
        #expect(!order.contains(.aetherEngine))
        #expect(order.contains(.vlcKit))
    }

    @Test
    func `live HLS starts with AVPlayer, which plays real HLS`() {
        let order = PlaybackEngineKind.defaultPriority(for: request("http://h/live/u/p/1.m3u8", .live))
        #expect(order.first == .avPlayer)
        #expect(!order.contains(.aetherEngine))
    }

    @Test
    func `an address with no extension is treated as readable by AVPlayer`() {
        let order = PlaybackEngineKind.defaultPriority(for: request("http://h/stream/1", .movie))
        #expect(order.first == .avPlayer)
    }

    @Test
    func `a person's choice goes first, even AetherEngine on live`() {
        let live = request("http://h/live/u/p/1.ts", .live)
        #expect(PlaybackEngineKind.order(preferred: .aetherEngine, for: live).first == .aetherEngine)
        #expect(PlaybackEngineKind.order(preferred: .vlcKit, for: live).first == .vlcKit)
        let rest = PlaybackEngineKind.order(preferred: .vlcKit, for: live).dropFirst()
        #expect(
            Array(rest) == [.lumeEngine, .avPlayer, .ksPlayer],
            "the others follow in the default order, without repeating the choice"
        )
    }

    @Test
    func `without a choice the default order is used`() {
        let film = request("http://h/movie/u/p/1.mkv", .movie)
        #expect(PlaybackEngineKind.order(preferred: nil, for: film) == PlaybackEngineKind.defaultPriority(for: film))
    }
}
