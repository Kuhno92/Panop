import Foundation
import PanopCore
import Testing

@Suite("what a provider means by a trailer")
struct TrailerSourceTests {
    private let id = "aqz-KE-bpKQ"

    @Test
    func `a bare id is a YouTube video`() {
        #expect(TrailerSource(id) == .youtube(id: id))
        #expect(TrailerSource("  \(id)\n") == .youtube(id: id))
    }

    @Test(arguments: [
        "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
        "http://youtube.com/watch?v=aqz-KE-bpKQ&t=30s",
        "https://m.youtube.com/watch?feature=share&v=aqz-KE-bpKQ",
        "https://youtu.be/aqz-KE-bpKQ",
        "https://youtu.be/aqz-KE-bpKQ?si=abc",
        "https://www.youtube.com/embed/aqz-KE-bpKQ",
        "https://www.youtube-nocookie.com/embed/aqz-KE-bpKQ?rel=0",
        "https://www.youtube.com/shorts/aqz-KE-bpKQ",
        "https://www.youtube.com/live/aqz-KE-bpKQ",
        "youtube.com/watch?v=aqz-KE-bpKQ",
        "www.youtube.com/watch?v=aqz-KE-bpKQ",
        "youtu.be/aqz-KE-bpKQ"
    ])
    func `every way of writing a YouTube address gives the id`(text: String) {
        #expect(TrailerSource(text) == .youtube(id: "aqz-KE-bpKQ"))
    }

    @Test
    func `a video file or stream is played by a player`() throws {
        #expect(try TrailerSource("https://cdn.example/trailers/film.mp4") ==
            .media(#require(URL(string: "https://cdn.example/trailers/film.mp4"))))
        #expect(TrailerSource("http://cdn.example/a/b.m3u8?token=1") ==
            URL(string: "http://cdn.example/a/b.m3u8?token=1").map(TrailerSource.media))
        #expect(TrailerSource("https://cdn.example/x.MOV") != nil)
    }

    @Test
    func `another page, or a YouTube page with no one video, is the browser's`() throws {
        #expect(try TrailerSource("https://www.imdb.com/video/vi123/") ==
            .web(#require(URL(string: "https://www.imdb.com/video/vi123/"))))
        #expect(try TrailerSource("https://www.youtube.com/playlist?list=PL123") ==
            .web(#require(URL(string: "https://www.youtube.com/playlist?list=PL123"))))
        #expect(try TrailerSource("https://www.youtube.com/@channel") ==
            .web(#require(URL(string: "https://www.youtube.com/@channel"))))
    }

    @Test
    func `nothing, or what is no address, is no trailer`() {
        #expect(TrailerSource(nil) == nil)
        #expect(TrailerSource("") == nil)
        #expect(TrailerSource("   ") == nil)
        #expect(TrailerSource("not a link") == nil)
        #expect(TrailerSource("ftp://example.com/a.mp4") == nil)
        // Eleven characters that are not an id.
        #expect(TrailerSource("hello world") == nil)
    }

    @Test
    func `an id with a wrong character is not an id`() {
        #expect(!TrailerSource.isVideoID("aqz-KE-bpK"))
        #expect(!TrailerSource.isVideoID("aqz-KE-bpKQQ"))
        #expect(!TrailerSource.isVideoID("aqz KE bpKQ"))
        #expect(TrailerSource.isVideoID("A_1-b_C-d_E"))
    }
}
