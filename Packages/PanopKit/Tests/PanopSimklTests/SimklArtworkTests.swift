import Foundation
import PanopCore
import PanopDiscover
@testable import PanopSimkl
import Testing

@Suite("Simkl artwork")
struct SimklArtworkTests {
    @Test func `a fanart path becomes the wide image's address`() {
        #expect(
            SimklArtwork.fanartURL("19/19818287730a769e81")?.absoluteString
                == "https://simkl.in/fanart/19/19818287730a769e81_w.webp"
        )
    }

    @Test(arguments: ["", "../etc/passwd", "/absolute"])
    func `an odd path gives no address`(path: String) {
        #expect(SimklArtwork.fanartURL(path) == nil)
    }

    @Test func `a list file's fanart travels with the title and its entry`() throws {
        let file = Data("""
        [{"title":"A","url":"/movies/1/a","fanart":"19/abc","ids":{"tmdb":"11"}},
         {"title":"B","url":"/movies/2/b","fanart":"","ids":{"tmdb":22}}]
        """.utf8)
        let titles = try #require(SimklFile.titles(from: file, kind: .movie))
        #expect(titles.map(\.fanart) == ["19/abc", nil])
        #expect(SimklLists.entries(of: titles).map(\.fanart) == ["19/abc", nil])
    }
}
