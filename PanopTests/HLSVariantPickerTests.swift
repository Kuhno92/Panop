import Foundation
@testable import Panop
import PanopPlayback
import Testing

@Suite("HLS variant picker")
struct HLSVariantPickerTests {
    private let multivariant = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=1000000
    low.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=3000000
    high.m3u8
    """

    private func item(_ url: String) -> PlaybackItem {
        PlaybackItem(url: url, headers: ["Referer": "https://site.example/"], userAgent: "Agent/1")
    }

    @Test
    func `a multivariant playlist becomes a local one-variant file`() async throws {
        let seen = Box()
        let choice = await HLSVariantPicker.choose(for: item("https://cdn.example/live/master.m3u8")) { request in
            seen.request = request
            return Data(multivariant.utf8)
        }
        let file = try #require(choice.file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(choice.address == file.absoluteString)
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("https://cdn.example/live/high.m3u8"))
        #expect(!written.contains("low.m3u8"))
        #expect(seen.request?.value(forHTTPHeaderField: "Referer") == "https://site.example/")
        #expect(seen.request?.value(forHTTPHeaderField: "User-Agent") == "Agent/1")
    }

    @Test
    func `a failed fetch leaves the original address`() async {
        struct Down: Error {}
        let choice = await HLSVariantPicker.choose(for: item("https://cdn.example/a.m3u8")) { _ in throw Down() }

        #expect(choice.address == "https://cdn.example/a.m3u8")
        #expect(choice.file == nil)
    }

    @Test
    func `a playlist with nothing to simplify leaves the original address`() async {
        let media = "#EXTM3U\n#EXTINF:6,\nseg.ts\n"
        let choice = await HLSVariantPicker.choose(for: item("https://cdn.example/a.m3u8")) { _ in Data(media.utf8) }

        #expect(choice.file == nil)
    }

    @Test
    func `an oversized answer is ignored`() async {
        let huge = Data(repeating: 0x23, count: 600 * 1024)
        let choice = await HLSVariantPicker.choose(for: item("https://cdn.example/a.m3u8")) { _ in huge }

        #expect(choice.file == nil)
    }

    @Test
    func `only http playlists are fetched at all`() async {
        let fetched = Box()
        for address in [
            "https://cdn.example/stream.ts",
            "https://cdn.example/stream",
            "file:///tmp/a.m3u8",
            "rtmp://x/a.m3u8"
        ] {
            let choice = await HLSVariantPicker.choose(for: item(address)) { request in
                fetched.request = request
                return Data()
            }
            #expect(choice.address == address)
        }
        #expect(fetched.request == nil)
    }

    private final class Box: @unchecked Sendable {
        var request: URLRequest?
    }
}
